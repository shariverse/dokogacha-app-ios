//
//  AddCandidateModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-08 候補を追加（場所を探す）と S-09 投稿の確認（F-10）の状態と操作。
///
/// - ルームと候補を購読し（`observe()`。画面の `.task` で呼ぶ）、検索結果の行の「追加」「追加済み」「上限」と「n/上限」を決める
/// - 検索欄と結果は `search`（`PlaceSearchModel`。0.3 秒のデバウンス）
/// - 「追加」で S-09（`draft`）を開く。ほかの人が同じ場所を投稿していれば、S-09 を開かずに重複の確認（`duplicatePrompt`）を出す
/// - 「候補に追加」で `addCandidate` を呼ぶ。追加できたらトースト「候補に追加しました」を出して S-07 に戻る（`finish`）。
///   サーバーが重複（`{ duplicateOf }`）を返したら、重複の確認を出す。上限・状態などのエラーはトースト
/// - 重複の確認の「いいねする」で、その候補にいいねして S-07 に戻る（02 の F-10。自分の投稿・いいね済みなら、いいねせずに戻る）
///
/// S-09 はシートなので、シートを出している間のトーストはシートの中の `sheetToasts` に出す（アプリの根元のトーストはシートの後ろに隠れるため）。
/// 成功のトーストは S-07 に戻ってから見えるよう、アプリの根元の `toasts` に出す。
@Observable
final class AddCandidateModel {
    /// 追加できたときのトースト（03 の S-09）
    static let addedMessage: LocalizedStringResource = "候補に追加しました"
    /// いいねの書き込みに失敗したときのトースト（S-07 のいいねと同じ）
    static let likeFailureMessage: LocalizedStringResource = "通信できませんでした"
    /// ひとことの文字数（02 の §3.1「最大40文字」）
    static let noteLength = DomainConstants.Limits.noteLength

    /// ルームの ID
    let roomID: String
    /// 自分の uid
    let userID: String
    /// 検索欄と結果
    @ObservationIgnored let search: PlaceSearchModel
    /// 選んでいるタブ
    var tab = Tab.search
    /// 購読で届いたルーム
    private(set) var room: Room?
    /// 購読で届いた候補
    private(set) var candidates: [Identified<Candidate>] = []
    /// 候補の最初の値が届いたか（届くまでは「追加」を押させない。追加済み・上限が分からないため）
    private(set) var hasLoadedCandidates = false
    /// S-09 で確かめている投稿（nil なら S-09 を出さない）
    var draft: Draft?
    /// S-09 のひとこと
    var note = ""
    /// S-09 の参考 URL
    var url = ""
    /// `addCandidate` を送っている途中か（二重に送らない・シートを閉じさせない）
    private(set) var isSubmitting = false
    /// 重複の確認（nil なら出さない）
    var duplicatePrompt: DuplicatePrompt?
    /// 重複の確認から、いいねを送っている途中か
    private(set) var isLiking = false
    /// S-07 に戻る（入ったら画面が戻る）
    private(set) var finish: Finish?

    /// S-09 のシートの中に出すトースト
    @ObservationIgnored let sheetToasts: DGToastCenter

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// 送っている `addCandidate`（画面が消えたら止める）
    @ObservationIgnored private var submitTask: Task<Void, Never>?
    /// 送っているいいね（画面が消えたら止める）
    @ObservationIgnored private var likeTask: Task<Void, Never>?
    /// 購読が失敗しているか（失敗が続いてもトーストは 1 回）
    @ObservationIgnored private var isSubscriptionFailing = false

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: ルーム・候補の購読と、いいねの書き込みの窓口
    ///   - functions: `addCandidate` を呼ぶ窓口
    ///   - places: 場所検索の窓口（MapKit か擬似の検索）
    ///   - toasts: アプリの根元のトースト（成功と、S-08 での通信エラー）
    ///   - sheetToasts: S-09 のシートの中のトースト（既定は新しく作る）
    ///   - sleep: 検索まで待つ処理（テストでは手で進めるものを渡す）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        places: any PlaceSearchService,
        toasts: DGToastCenter,
        sheetToasts: DGToastCenter = DGToastCenter(),
        sleep: @escaping PlaceSearchModel.Sleep = { try await Task.sleep(for: $0) },
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.roomID = roomID
        self.userID = userID
        self.repository = repository
        self.functions = functions
        self.toasts = toasts
        self.sheetToasts = sheetToasts
        self.resubscribeDelay = resubscribeDelay
        search = PlaceSearchModel(places: places, toasts: toasts, sleep: sleep)
    }

    // MARK: - 表示の値

    /// 1 人あたりの投稿数（ルームが届くまでは 0）
    var postLimit: Int {
        room?.settings.postLimit ?? 0
    }

    /// 自分の投稿の数
    var myPostCount: Int {
        PlaceAddAvailability.myPostCount(in: candidates, userID: userID)
    }

    /// ルームが投稿を受け付ける状態か（F-10「投稿できるのは open/unlocked のときだけ」）
    var acceptsCandidates: Bool {
        room.map { RoomCandidateRow.likeableStatuses.contains($0.status) } ?? false
    }

    /// 検索結果の行の状態（「追加」「追加済み」「上限」）。候補がまだ届いていなければ押せない
    func availability(of place: SearchedPlace) -> PlaceAddAvailability {
        PlaceAddAvailability.of(
            place.place,
            candidates: candidates,
            userID: userID,
            postLimit: postLimit,
            acceptsCandidates: acceptsCandidates && hasLoadedCandidates
        )
    }

    /// ひとことの検証（文字数とエラー。`NameValidation` と同じ規則）
    var noteCheck: NameInputCheck {
        NameInputCheck(note, length: Self.noteLength)
    }

    /// 参考 URL の検証
    var urlInput: CandidateRules.URLInput {
        CandidateRules.validatedURL(url)
    }

    /// 送る入力。入力が正しくなければ nil
    var request: AddCandidateRequest? {
        guard let draft, let note = CandidateRules.validatedNote(note) else {
            return nil
        }
        let url: String?
        switch urlInput {
        case .none:
            url = nil
        case let .valid(value):
            url = value
        case .invalid:
            return nil
        }
        return AddCandidateRequest(
            roomId: roomID,
            place: draft.place.place,
            category: draft.category,
            note: note,
            url: url,
            fromPastIdeaId: nil
        )
    }

    /// 「候補に追加」を押せるか（入力が正しく、送っている途中でない）
    var canSubmit: Bool {
        request != nil && !isSubmitting && !isLiking && finish == nil
    }

    /// いまの画面に合わせたトースト（S-09 を出していればシートの中）
    private var currentToasts: DGToastCenter {
        draft == nil ? toasts : sheetToasts
    }

    // MARK: - 購読

    /// ルームと候補を購読し、呼んだ `Task` が cancel されるまで続ける（画面の `.task` で呼ぶ）
    func observe() async {
        async let room: Void = followRoom()
        async let candidates: Void = followCandidates()
        _ = await (room, candidates)
    }

    /// ルームを購読し続ける
    private func followRoom() async {
        await follow(subscribe: { repository.room(id: roomID) }, apply: applyRoom)
    }

    /// 候補を購読し続ける
    private func followCandidates() async {
        await follow(subscribe: { repository.candidates(roomID: roomID) }, apply: applyCandidates)
    }

    /// 購読を続ける。失敗で終わったら、少し待って購読し直す。cancel されたら、流れ残りの値を映さずに終わる
    private func follow<Value: Sendable>(
        subscribe: () -> AsyncStream<LiveUpdate<Value>>,
        apply: (Value) -> Void
    ) async {
        while !Task.isCancelled {
            for await update in subscribe() {
                guard !Task.isCancelled else {
                    return
                }
                switch update {
                case let .value(value):
                    isSubscriptionFailing = false
                    apply(value)
                case let .failure(error):
                    noteFailure(error)
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
    }

    /// 購読の失敗でトーストを出す（失敗が続いても 1 回）
    private func noteFailure(_ error: AppError) {
        guard !error.isCancellation, !isSubscriptionFailing else {
            return
        }
        isSubscriptionFailing = true
        currentToasts.show(text: error.message)
    }

    /// 届いたルームを映す
    private func applyRoom(_ value: Identified<Room>?) {
        room = value?.value
    }

    /// 届いた候補を映す
    private func applyCandidates(_ value: [Identified<Candidate>]) {
        candidates = value
        hasLoadedCandidates = true
    }

    // MARK: - 追加

    /// 検索結果の「追加」が押された。追加できれば S-09 を開き、ほかの人が同じ場所を投稿していれば重複の確認を出す
    func addTapped(_ place: SearchedPlace) {
        guard draft == nil, duplicatePrompt == nil, finish == nil else {
            return
        }
        switch availability(of: place) {
        case .addable:
            note = ""
            url = ""
            draft = Draft(place: place, category: place.category)
        case let .duplicate(candidateID):
            duplicatePrompt = DuplicatePrompt(candidateID: candidateID)
        case .added, .limitReached, .unavailable:
            break
        }
    }

    /// S-09 でカテゴリを選び直した
    func selectCategory(_ category: PlaceCategory) {
        guard !isSubmitting else {
            return
        }
        draft?.category = category
    }

    /// S-09 の閉じるが押された（送っている途中は閉じない）
    func closeDraft() {
        guard !isSubmitting, !isLiking else {
            return
        }
        draft = nil
    }

    /// 「候補に追加」が押された。`addCandidate` を送る（送っている途中なら何もしない）。
    ///
    /// `isSubmitting` は Task が動き出してから立つので、始めた Task が残っている間も押せないことにする
    func submitTapped() {
        guard canSubmit, submitTask == nil else {
            return
        }
        submitTask = Task {
            await submit()
            if !Task.isCancelled {
                submitTask = nil
            }
        }
    }

    /// 候補を追加する。
    ///
    /// - 追加できたら、トースト「候補に追加しました」を出して S-07 に戻る
    /// - 重複なら、重複の確認を出す（S-09 は開いたまま）
    /// - 失敗したら、S-09 のトーストに文言を出し、入力をそのままにもう一度押せるようにする。cancel のときは何もしない
    func submit() async {
        guard canSubmit, let request else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await functions.addCandidate(request)
            guard !Task.isCancelled else {
                return
            }
            switch result {
            case .added:
                toasts.show(Self.addedMessage)
                finishFlow()
            case let .duplicate(candidateID):
                duplicatePrompt = DuplicatePrompt(candidateID: candidateID)
            }
        } catch {
            let appError = AppError.wrapping(error)
            if !appError.isCancellation, !Task.isCancelled {
                currentToasts.show(text: appError.message)
            }
        }
    }

    // MARK: - 重複の確認

    /// 重複の確認の「いいねする」が押された（`likeDuplicate(_:)` を `Task` で動かす）
    func likeDuplicateTapped(_ prompt: DuplicatePrompt) {
        guard likeTask == nil else {
            return
        }
        likeTask = Task {
            await likeDuplicate(prompt)
            if !Task.isCancelled {
                likeTask = nil
            }
        }
    }

    /// 重複した候補にいいねして S-07 に戻る（02 の F-10「「いいねする」でその候補にいいね（自分の投稿だった場合はいいねせず閉じる）」）。
    ///
    /// いいね済みの候補もいいねせずに戻る。失敗したらトースト「通信できませんでした」を出し、この画面に留まる
    func likeDuplicate(_ prompt: DuplicatePrompt) async {
        guard !isLiking, !isSubmitting, finish == nil else {
            return
        }
        duplicatePrompt = nil
        let candidate = candidates.first { $0.id == prompt.candidateID }
        if let candidate, candidate.postedBy == userID || candidate.likedBy.contains(userID) {
            finishFlow()
            return
        }
        isLiking = true
        defer { isLiking = false }
        do {
            try await repository.setLike(true, candidateID: prompt.candidateID, roomID: roomID, userID: userID)
            guard !Task.isCancelled else {
                return
            }
            finishFlow()
        } catch {
            if !AppError.wrapping(error).isCancellation, !Task.isCancelled {
                currentToasts.show(Self.likeFailureMessage)
            }
        }
    }

    /// 重複の確認のキャンセルが押された（その画面に留まる）
    func dismissDuplicatePrompt() {
        duplicatePrompt = nil
    }

    // MARK: - 終わり

    /// S-07 に戻る。S-09 を出していれば閉じる
    private func finishFlow() {
        finish = draft == nil ? .fromList : .fromSheet
        draft = nil
    }

    /// 画面が消えたとき、待っている検索・送っている途中の追加といいねを止める（結果を待つ相手がいないため。cancel ではトーストを出さない）。
    ///
    /// Task は self を持つので、画面の `onDisappear` から必ず呼ぶ（Model の `deinit` では止められない）
    func cancelTasks() {
        search.cancel()
        submitTask?.cancel()
        submitTask = nil
        likeTask?.cancel()
        likeTask = nil
    }
}

extension AddCandidateModel {
    /// タブ（03 の S-08「場所を探す」「過去のアイデア」）
    enum Tab: Hashable {
        /// 場所を探す
        case search
        /// 過去のアイデア（中身はタスク 31）
        case pastIdeas
    }

    /// S-09 で確かめている投稿（シートの行き先）
    struct Draft: Identifiable, Equatable {
        /// 選んだ場所
        let place: SearchedPlace
        /// カテゴリ（自動判定の値から始め、選び直せる）
        var category: PlaceCategory

        var id: String {
            place.id
        }
    }

    /// 重複の確認（「すでに候補にあります。いいねしますか？」）
    struct DuplicatePrompt: Identifiable, Equatable {
        /// 同じ場所の既存の候補の ID
        let candidateID: String

        var id: String {
            candidateID
        }
    }

    /// S-07 に戻る理由（どこから戻るか）
    enum Finish: Equatable {
        /// S-09 のシートから（シートが閉じ終わってから S-08 を外す）
        case fromSheet
        /// S-08 の一覧から（すぐに S-08 を外す）
        case fromList
    }
}
