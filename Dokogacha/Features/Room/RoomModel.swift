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
///
/// いいね（F-20）は楽観的更新にする:
/// - 押したらすぐに `pendingLikes` に入れて表示を変え、直接の書き込み（`setLike`）を送る
/// - 送れたら、次に届いた候補の値で確定する（購読の値をそのまま映す。サーバーに拒まれたときも、SDK が戻した値が届く）
/// - 送る前に分かる失敗（接続できないなど）なら、表示を戻してトースト「通信できませんでした」を出す
/// - 送っている途中（確定する前）は同じ候補をもう一度押しても何もしない（二度押し）。自分の投稿・`drawn`・`closed` も押せない
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
        /// ルームが無い（削除された）
        case missing
    }

    /// 下部の「ガチャを回す」の状態（03 の S-07 の GachaCTA）
    enum GachaButtonState: Equatable {
        /// 解禁している（「ガチャを回す」。押せる）
        case ready
        /// 解禁していない（「準備OKが揃うと回せます」。押せない）
        case waiting
    }

    /// 送っている途中のいいね
    struct PendingLike: Equatable {
        /// 付けるか（false なら外す）
        let liked: Bool
        /// 送り終えたか（送り終えたら、次に届いた候補の値で確定する）
        var isSent = false
    }

    /// 購読の種類（どれが失敗しているかを覚えて、トーストを 1 回にする）
    private enum Source: Hashable {
        case room
        case members
        case candidates
    }

    /// いいねの書き込みに失敗したときのトースト（goal のタスク 19〜21「失敗したら戻してトースト「通信できませんでした」」）
    static let likeFailureMessage: LocalizedStringResource = "通信できませんでした"

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
    private(set) var pendingLikes: [String: PendingLike] = [:]
    /// NEW の判定に使う、画面を開いて最初に届いた自分の `lastSeenAt`（まだ届いていなければ nil）
    private(set) var seenBaseline: Date?

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// いま失敗している購読
    @ObservationIgnored private var failingSources: Set<Source> = []

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: 購読と直接の書き込みの窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.roomID = roomID
        self.userID = userID
        self.repository = repository
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
    }

    // MARK: - 表示の値

    /// 候補一覧の行（新しい順。送っている途中のいいねを映したもの）
    var rows: [RoomCandidateRow] {
        guard let room else {
            return []
        }
        return RoomCandidateRow.rows(
            candidates: candidates,
            members: members,
            room: room,
            myUserID: userID,
            lastSeenAt: seenBaseline,
            pendingLikes: pendingLikes.mapValues(\.liked)
        )
    }

    /// NEW の候補の数（「前回見たあとに N件の候補が増えました」の N）
    var newCount: Int {
        rows.count(where: \.isNew)
    }

    /// 候補が 1 件も無いと分かったか（空の表示を出す）
    var isEmpty: Bool {
        hasLoadedCandidates && candidates.isEmpty
    }

    /// 行き先表示の「カプセル N個」（引き直しで外れた候補を除いた数。ホームのカードと同じ数え方）
    var capsuleCount: Int {
        guard let room else {
            return 0
        }
        return HomeRoomCard.capsuleCount(of: room)
    }

    /// 自分がルームの作成者か（設定の入口を出す）
    var isOwner: Bool {
        room?.ownerId == userID
    }

    /// 準備OKの人数（メンバーを読めていればその数、読めていなければルームの `readyCount`）
    var readyCount: Int {
        members.isEmpty ? room?.readyCount ?? 0 : members.count(where: \.ready)
    }

    /// メンバーの人数
    var memberCount: Int {
        members.isEmpty ? room?.memberCount ?? 0 : members.count
    }

    /// 自分の投稿の数（「あなたの投稿 n/上限件」の n）
    var myPostCount: Int {
        candidates.count { $0.postedBy == userID }
    }

    /// 候補を追加できる状態か（F-10「投稿できるのは open/unlocked のときだけ」）
    var acceptsCandidates: Bool {
        room.map { RoomCandidateRow.likeableStatuses.contains($0.status) } ?? false
    }

    /// 下部の「ガチャを回す」の状態。`drawn`・`closed` は結果の画面（タスク 28）を出すので、ボタンを出さない（nil）
    var gachaButtonState: GachaButtonState? {
        switch room?.status {
        case .unlocked: .ready
        case .open: .waiting
        case .drawn, .closed, nil: nil
        }
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
                case let .failure(error):
                    noteFailure(error, from: source)
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
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

    /// 届いたルームを映す。いいねを受け付けない状態になったら、送っている途中のいいねの表示を捨てる
    private func applyRoom(_ value: Identified<Room>?) {
        guard let value else {
            room = nil
            loadState = .missing
            pendingLikes = [:]
            return
        }
        room = value.value
        loadState = .loaded
        if !RoomCandidateRow.likeableStatuses.contains(value.status) {
            pendingLikes = [:]
        }
    }

    /// 届いたメンバーを映す。自分の `lastSeenAt` は最初に届いた値だけを NEW の判定に使う
    private func applyMembers(_ value: [Identified<Member>]) {
        members = value
        if seenBaseline == nil, let me = value.first(where: { $0.id == userID }) {
            seenBaseline = me.lastSeenAt
        }
    }

    /// 届いた候補を映す。送り終えたいいねは、この値で確定する（表示は購読の値に戻す）。消えた候補のいいねも捨てる
    private func applyCandidates(_ value: [Identified<Candidate>]) {
        candidates = value
        hasLoadedCandidates = true
        let ids = Set(value.map(\.id))
        pendingLikes = pendingLikes.filter { id, pending in
            ids.contains(id) && !pending.isSent
        }
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
        pendingLikes[candidateID] = PendingLike(liked: liked)
        do {
            try await repository.setLike(liked, candidateID: candidateID, roomID: roomID, userID: userID)
            guard pendingLikes[candidateID] != nil else {
                return
            }
            // 送っている間に購読の値がもう追いついていれば確定し、まだなら次に届いた値で確定する
            if candidates.first(where: { $0.id == candidateID })?.likedBy.contains(userID) == liked {
                pendingLikes[candidateID] = nil
            } else {
                pendingLikes[candidateID]?.isSent = true
            }
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
