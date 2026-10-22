//
//  RoomModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-07 ルームの状態（ルーム・メンバー・候補の購読と、いいね・`lastSeenAt` の書き込み）。
///
/// 購読（05 の §6「ルーム画面では room・members・candidates を購読」）は `observe()` の中で 3 つを `async let` で並べて動かす。
/// 画面（`RoomView`）は `.task` で `observe()` を呼ぶので、画面が消えて `.task` が cancel されると 3 つとも止まる
/// （Model のプロパティに `Task` を持たないので、画面を素早く出し直しても、前の後片付けが新しい購読を止めることがない）。
///
/// 通信エラーでは画面を壊さない: 購読が失敗したら、出していた値のまま少し待って購読し直す。
/// トーストは「どの購読も失敗していない状態から失敗したとき」の 1 回だけ出し、失敗した購読が値を受け取り直すまで出し直さない。
/// ただし permission-denied（ルームが削除された・退出した・作成者に削除された・無いルームを開いた）は、購読し直しても読めないので、
/// 購読し直さずトーストも出さずに `.missing`（「ルームが見つかりません」）にする。
///
/// いいね（F-20）は楽観的更新にする:
/// - 押したらすぐに `pendingLikes` に入れて表示を変え、直接の書き込み（`setLike`）を送る
/// - 押した候補の自分のいいねが、届いた値で楽観的な値と一致したときに確定する（`OptimisticWrite`）。
///   送っている途中にほかの人のいいねや別の候補の変化が届いても、押した候補の値が追いつくまでは楽観的な表示を続ける
/// - 送る前に分かる失敗（接続できないなど）なら、表示を戻してトースト「通信できませんでした」を出す
/// - 送っている途中（確定する前）は同じ候補をもう一度押しても何もしない（二度押し）。自分の投稿・`drawn`・`closed` も押せない
///
/// 準備OK（F-30）もいいねと同じ形の楽観的更新にする（自分のメンバーの `ready` が楽観的な値と一致したら確定する）。
/// ボタンを出すかは `room.status`（`open`・`unlocked`）で決め、ヒントの「あと N人」だけに `UnlockJudge` を使う（`ReadyHint`）。
///
/// 強制解禁（F-32）は作成者だけ・`open` のときだけ出し、確認のダイアログ（02 の §5.3）を挟んで Callable の `forceUnlock` を呼ぶ。
/// 送っている途中は二重に送らず、画面の戻る操作を止める。失敗したら `AppError` の文言のトーストを出す。成功したら購読の
/// `unlocked` で全員の画面が「ガチャ解禁！」になる（自分の画面も購読の値で変わる）。
/// ほかの人がガチャを回した（F-41）ら、`DrawReplay` で決めた抽選を `drawToReplay` に入れ、画面が S-13 を開く。
///
/// `lastSeenAt`（F-12 の NEW）は 02 の §3.3「ルーム画面を離れたときに更新する」のとおり、画面が消えたとき・アプリが裏に回ったときに書く。
/// NEW の判定には、画面を開いて最初に届いた自分の `lastSeenAt` を使い続ける（画面を出している間は NEW を消さない）。
@Observable
final class RoomModel {
    /// ルームの読み込みの状態
    enum LoadState: Equatable {
        /// まだルームが届いていない（部品の形を保ったまま `redacted` で出す）
        case loading
        /// ルームが届いた
        case loaded
        /// ルームが無い・読めなくなった（削除された・退出した・作成者に削除された）
        case missing
    }

    /// 下部の「ガチャを回す」の状態（03 の S-07 の GachaCTA）
    enum GachaButtonState: Equatable {
        /// 解禁している（「ガチャを回す」。押せる）
        case ready
        /// 解禁していない（「準備OKが揃うと回せます」。押せない）
        case waiting
    }

    /// 購読の種類（どれが失敗しているかを覚えて、トーストを 1 回にする）
    private enum Source: Hashable {
        case room
        case members
        case candidates
    }

    /// いいねの書き込みに失敗したときのトースト（goal のタスク 19〜21「失敗したら戻してトースト「通信できませんでした」」）
    static let likeFailureMessage: LocalizedStringResource = "通信できませんでした"
    /// 準備OKの書き込みに失敗したときのトースト（いいねと同じ）
    static let readyFailureMessage: LocalizedStringResource = "通信できませんでした"

    /// ルームの ID
    let roomID: String
    /// 自分の uid
    let userID: String
    /// ルームの読み込みの状態
    private(set) var loadState: LoadState = .loading
    /// 購読で届いたルーム
    private(set) var room: Room?
    /// 購読で届いたメンバー（参加の早い順）
    private(set) var members: [Identified<Member>] = []
    /// 購読で届いた候補
    private(set) var candidates: [Identified<Candidate>] = []
    /// 候補の最初の値が届いたか（届くまでは空の表示を出さない）
    private(set) var hasLoadedCandidates = false
    /// 送っている途中のいいね（候補の ID ごと）
    private(set) var pendingLikes: [String: OptimisticWrite<Bool>] = [:]
    /// 送っている途中の自分の準備OK（無ければ nil）
    private(set) var pendingReady: OptimisticWrite<Bool>?
    /// NEW の判定に使う、画面を開いて最初に届いた自分の `lastSeenAt`（まだ届いていなければ nil）
    private(set) var seenBaseline: Date?
    /// 強制解禁の確認のダイアログを出しているか
    var isConfirmingForceUnlock = false
    /// 強制解禁を送っている途中か（二重に送らない・画面を閉じさせない）
    private(set) var isForceUnlocking = false
    /// ほかの人が回したので、ガチャ（S-13）を開いて演出を再生する抽選の ID（開いたら `replayOpened()` で消す）
    private(set) var drawToReplay: String?

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let functions: any FunctionsClient
    /// 確認のダイアログから始めた強制解禁（二重に始めないために持つ）
    @ObservationIgnored private var forceUnlockTask: Task<Void, Never>?
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// ガチャの演出を見終えた抽選
    @ObservationIgnored private let seenDraws: any SeenDrawStore
    /// いま失敗している購読
    @ObservationIgnored private var failingSources: Set<Source> = []

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: 購読と直接の書き込みの窓口（Firebase か擬似のサーバー）
    ///   - functions: `forceUnlock` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    ///   - seenDraws: ガチャの演出を見終えた抽選（ほかの人が回したときに S-13 を開くかを決める）
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard,
        seenDraws: any SeenDrawStore = InMemorySeenDrawStore()
    ) {
        self.roomID = roomID
        self.userID = userID
        self.repository = repository
        self.functions = functions
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
        self.seenDraws = seenDraws
    }

    // MARK: - 購読

    /// ルーム・メンバー・候補を購読し、呼んだ `Task` が cancel されるまで続ける（cancel されたら 3 つとも止める）
    func observe() async {
        async let room: Void = followRoom()
        async let members: Void = followMembers()
        async let candidates: Void = followCandidates()
        _ = await (room, members, candidates)
    }

    /// ルームを購読し続ける
    private func followRoom() async {
        await follow(.room, subscribe: { repository.room(id: roomID) }, apply: applyRoom)
    }

    /// メンバーを購読し続ける
    private func followMembers() async {
        await follow(.members, subscribe: { repository.members(roomID: roomID) }, apply: applyMembers)
    }

    /// 候補を購読し続ける
    private func followCandidates() async {
        await follow(.candidates, subscribe: { repository.candidates(roomID: roomID) }, apply: applyCandidates)
    }

    /// 購読を続ける。失敗で終わったら、少し待って購読し直す。cancel されたら、流れ残りの値を映さずに終わる
    /// - Parameters:
    ///   - source: 購読の種類
    ///   - subscribe: 購読を始める処理
    ///   - apply: 値が届いたときに映す処理
    private func follow<Value: Sendable>(
        _ source: Source,
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
                    failingSources.remove(source)
                    apply(value)
                case let .failure(error) where error.isPermissionDenied:
                    markMissing()
                    return
                case let .failure(error):
                    noteFailure(error, from: source)
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
    }

    /// ルームを読めなくなった。`.missing` にし、出していた値と送っている途中の表示を捨てる（購読し直さない）
    private func markMissing() {
        (room, members, candidates, loadState, pendingLikes, pendingReady) = (nil, [], [], .missing, [:], nil)
        failingSources.removeAll()
    }

    /// 購読の失敗を覚え、どの購読も失敗していなかったときだけトーストを出す（失敗が続いても 1 回）
    private func noteFailure(_ error: AppError, from source: Source) {
        guard !error.isCancellation else {
            return
        }
        let wasHealthy = failingSources.isEmpty
        failingSources.insert(source)
        if wasHealthy {
            toasts.show(text: error.message)
        }
    }

    /// 届いたルームを映す。いいね・準備OKを受け付けない状態になったら、送っている途中の表示を捨てる
    /// （その状態では書き込みが拒まれ、一致する値が届かないため）
    private func applyRoom(_ value: Identified<Room>?) {
        guard let value else {
            room = nil
            loadState = .missing
            pendingLikes = [:]
            pendingReady = nil
            return
        }
        drawToReplay = DrawReplay.drawID(previous: room?.status, room: value.value, hasSeen: seenDraws.hasSeen(drawID:)) ?? drawToReplay
        room = value.value
        loadState = .loaded
        if !RoomCandidateRow.likeableStatuses.contains(value.status) {
            pendingLikes = [:]
        }
        if !Self.readyStatuses.contains(value.status) {
            pendingReady = nil
        }
    }

    /// 届いたメンバーを映す。送っている途中の準備OKは、自分の `ready` が一致したら確定し、自分がいなければ
    /// （削除された）捨てる。自分の `lastSeenAt` は最初に届いた値だけを NEW の判定に使う
    private func applyMembers(_ value: [Identified<Member>]) {
        members = value
        if var pending = pendingReady {
            if let me = value.first(where: { $0.id == userID }), !pending.received(me.ready) {
                pendingReady = pending
            } else {
                pendingReady = nil
            }
        }
        if seenBaseline == nil, let me = value.first(where: { $0.id == userID }) {
            seenBaseline = me.lastSeenAt
        }
    }

    /// 届いた候補を映す。送っている途中のいいねは、押した候補の自分のいいねが一致したら確定する（`OptimisticWrite`）。
    /// 消えた候補のいいねは捨てる（削除された候補へのいいねは拒まれ、一致する値が届かないため）
    private func applyCandidates(_ value: [Identified<Candidate>]) {
        candidates = value
        hasLoadedCandidates = true
        let byID = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, var pending) in pendingLikes {
            guard let candidate = byID[id] else {
                pendingLikes[id] = nil
                continue
            }
            pendingLikes[id] = pending.received(candidate.likedBy.contains(userID)) ? nil : pending
        }
    }

    /// S-13 を開いた（`drawToReplay` を消す）
    func replayOpened() {
        drawToReplay = nil
    }

    // MARK: - いいね

    /// いいねボタンが押された。付ける・外すを送る（`toggleLike(_:)` を `Task` で動かす）。
    ///
    /// 直接の書き込みは送った時点で返る（`RoomRepository`）ので、`Task` はすぐに終わる。画面が消えても止めない（送ったいいねは送る）
    func likeTapped(_ candidateID: String) {
        Task {
            await toggleLike(candidateID)
        }
    }

    /// いいねを付ける・外す（楽観的更新）。押せない候補・送っている途中の候補では何もしない
    func toggleLike(_ candidateID: String) async {
        guard pendingLikes[candidateID] == nil,
              let room, RoomCandidateRow.likeableStatuses.contains(room.status),
              let candidate = candidates.first(where: { $0.id == candidateID }),
              candidate.postedBy != userID else {
            return
        }
        let liked = !candidate.likedBy.contains(userID)
        pendingLikes[candidateID] = OptimisticWrite(liked)
        do {
            try await repository.setLike(liked, candidateID: candidateID, roomID: roomID, userID: userID)
            guard var pending = pendingLikes[candidateID] else {
                return
            }
            // 送っている間に一致した値が届いていれば・今の値がもう一致していれば確定し、まだなら一致した値が届いたときに確定する
            let current = candidates.first { $0.id == candidateID }?.likedBy.contains(userID)
            pendingLikes[candidateID] = pending.sent(current: current) ? nil : pending
        } catch {
            pendingLikes[candidateID] = nil
            if !AppError.wrapping(error).isCancellation {
                toasts.show(Self.likeFailureMessage)
            }
        }
    }

    // MARK: - lastSeenAt

    /// 画面を離れた（画面が消えた・アプリが裏に回った）。`lastSeenAt` を今にする（`recordSeen()` を `Task` で動かす）
    func leftRoom() {
        Task {
            await recordSeen()
        }
    }

    /// 自分の `lastSeenAt` をサーバーの今の時刻にする（F-12）。
    ///
    /// 失敗してもトーストは出さない（画面を離れるときの裏の書き込みで、次に開いたときの NEW が多めに出るだけのため）
    func recordSeen() async {
        try? await repository.markSeen(roomID: roomID, userID: userID)
    }
}

extension RoomModel {
    // MARK: - 準備OK

    /// 「準備OK」「準備OKを取り消す」が押された。付ける・外すを送る（`toggleReady()` を `Task` で動かす。いいねと同じく画面が消えても止めない）
    func readyTapped() {
        Task {
            await toggleReady()
        }
    }

    /// 自分の準備OKを付ける・外す（楽観的更新）。`open`・`unlocked` 以外・メンバーを読めていない・送っている途中なら何もしない
    func toggleReady() async {
        guard pendingReady == nil, showsReadyButton,
              let me = members.first(where: { $0.id == userID }) else {
            return
        }
        let ready = !me.ready
        pendingReady = OptimisticWrite(ready)
        do {
            try await repository.setReady(ready, roomID: roomID, userID: userID)
            guard var pending = pendingReady else {
                return
            }
            let current = members.first { $0.id == userID }?.ready
            pendingReady = pending.sent(current: current) ? nil : pending
        } catch {
            pendingReady = nil
            if !AppError.wrapping(error).isCancellation {
                toasts.show(Self.readyFailureMessage)
            }
        }
    }

    // MARK: - 強制解禁

    /// 「強制解禁（作成者）」が押された。確認のダイアログを出す（出せないとき・送っている途中なら出さない）
    func forceUnlockTapped() {
        guard canForceUnlock, !isForceUnlocking else {
            return
        }
        isConfirmingForceUnlock = true
    }

    /// 確認のダイアログで「解禁する」が押された。強制解禁を始める（始めた Task が残っている間は受け付けない）。
    ///
    /// 画面が消えても止めない（作成者が解禁を決めたので、送ったものは送り切る。失敗のトーストは前の画面に出る）
    func confirmForceUnlockTapped() {
        guard forceUnlockTask == nil else {
            return
        }
        forceUnlockTask = Task { [weak self] in
            await self?.forceUnlock()
            self?.forceUnlockTask = nil
        }
    }

    /// 強制解禁する（`forceUnlock`）。作成者でない・`open` でない・送っている途中なら何もしない。
    ///
    /// 成功したら何もしない（購読の `unlocked` と `forcedUnlock` で表示が変わる）。失敗したら `AppError` の文言のトーストを出す
    func forceUnlock() async {
        guard canForceUnlock, !isForceUnlocking else {
            return
        }
        isForceUnlocking = true
        defer { isForceUnlocking = false }
        do {
            try await functions.forceUnlock(RoomRequest(roomId: roomID))
        } catch {
            let appError = AppError.wrapping(error)
            if !appError.isCancellation {
                toasts.show(text: appError.message)
            }
        }
    }
}
