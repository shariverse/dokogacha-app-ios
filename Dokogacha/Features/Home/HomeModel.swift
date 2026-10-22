//
//  HomeModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-02 ホームの状態（進行中のルームの購読）。
///
/// 自分が入っている進行中のルームを `RoomRepository.activeRooms` で購読し（05 の §6「ホームでは `rooms` を
/// `memberIds array-contains uid` で購読」）、カードのアバターと準備OKのために、並んでいるルームごとに `members` も購読する。
/// 画面（`HomeView`）は `.task` で `observe()` を呼び、画面が消えると cancel してすべての購読を止める。
///
/// メンバーの購読の `Task` は、それを始めた `observe()` の呼び出しが自分の局所の変数で持ち、終わるときに自分の分だけ止める。
/// Model のプロパティで持つと、画面を素早く出し直したとき（push と pop の繰り返し）に、前の `observe()` の後片付けが
/// 新しい `observe()` の始めた購読まで止めてしまうため。`Task` は self を弱く持ち、値を映すときだけ self を使う。
///
/// 通信エラーでは画面を壊さない:
/// - ルームの購読が失敗したら、トースト（続けて失敗しても 1 回だけ）を出し、出していた一覧（まだ無ければ読み込み中の形）のまま、
///   少し待って購読し直す
/// - メンバーの購読の失敗はトーストを出さずに読み直す（カードは人数だけ先に出せる。ルームから外れた直後の拒否でトーストを出さないため）
///
/// 「思い出のきっぷ」（03 の S-02 の 3・F-44）は、終了したルームを `RoomRepository.closedRooms` で購読し、
/// ルームごとに当選した候補 1 件だけを `candidate(roomID:candidateID:)` で購読して「◯◯ ゆき」を出す（候補をまるごと読まない）。
/// 終了したルームは増え続けるので、「すべて見る」を押すまでは 6 件（`MemoryTicket.queryLimit`）だけを読み、
/// 当選した候補は出す 5 枚の分だけ購読する。押したら上限なしで購読し直し、残りのルームの当選した候補も購読する。
/// 進行中のルームと並べて動かし（`async let`）、どちらも `observe()` を呼んだ `Task` の cancel で止まる。
/// 思い出のきっぷの購読の失敗はトーストを出さずに読み直す（同じ通信の失敗で、進行中のルームの購読が 1 回だけトーストを出す）。
@Observable
final class HomeModel {
    /// 進行中のルーム・思い出のきっぷの読み込みの状態
    enum RoomsState: Equatable {
        /// 最初の一覧がまだ届いていない（部品の形を保ったまま `redacted` で出す）
        case loading
        /// 一覧が届いた（空なら空の表示）
        case loaded
    }

    /// 自分の uid
    let userID: String
    /// 進行中のルームの読み込みの状態
    private(set) var roomsState: RoomsState = .loading
    /// 購読で届いた進行中のルーム
    private(set) var rooms: [Identified<Room>] = []
    /// ルームごとのメンバー（ルームの ID → 参加の早い順）
    private(set) var membersByRoom: [String: [Identified<Member>]] = [:]
    /// 思い出のきっぷの読み込みの状態
    private(set) var memoriesState: RoomsState = .loading
    /// 購読で届いた終了したルーム
    private(set) var closedRooms: [Identified<Room>] = []
    /// 終了したルームの当選した候補（ルームの ID → 候補）
    private(set) var winnersByRoom: [String: Candidate] = [:]
    /// 「すべて見る」を押したか（押したら 6 枚目からも出す）
    private(set) var showsAllMemories = false

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// 「すべて見る」が押されたことを、購読している `observe()` に伝える口（`observe()` の呼び出しごと）
    @ObservationIgnored private var showAllListeners: [UUID: () -> Void] = [:]

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - repository: ルームとメンバーの購読の窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        userID: String,
        repository: any RoomRepository,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.userID = userID
        self.repository = repository
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
    }

    /// 進行中のルームのカード（作成日時の新しい順）
    var cards: [HomeRoomCard] {
        HomeRoomCard.cards(rooms: rooms, members: membersByRoom)
    }

    /// 進行中のルームが 1 つも無いと分かったか（空の表示を出す）
    var isEmpty: Bool {
        roomsState == .loaded && cards.isEmpty
    }

    /// 思い出のきっぷ（新しい順。当選した候補が届いたルームだけ）
    var memoryTickets: [MemoryTicket] {
        MemoryTicket.tickets(rooms: closedRooms, winners: winnersByRoom)
    }

    /// ホームに出す思い出のきっぷ（「すべて見る」を押す前は 5 枚まで）
    var visibleMemoryTickets: [MemoryTicket] {
        MemoryTicket.visible(memoryTickets, showsAll: showsAllMemories)
    }

    /// 「すべて見る」を出すか
    var hasMoreMemories: Bool {
        MemoryTicket.hasMore(roomCount: closedRooms.count, showsAll: showsAllMemories)
    }

    /// 終了したルームが 1 つも無いと分かったか（空の表示を出す）
    var isMemoriesEmpty: Bool {
        memoriesState == .loaded && closedRooms.isEmpty
    }

    /// 思い出のきっぷを読み込み中の形で出すか（一覧がまだ届いていない・ルームはあるが当選した候補がまだ 1 件も届いていない）
    var isMemoriesLoading: Bool {
        memoriesState == .loading || (!closedRooms.isEmpty && memoryTickets.isEmpty)
    }

    /// 「すべて見る」が押された（終了したルームを上限なしで購読し直す）
    func showAllMemoriesTapped() {
        guard !showsAllMemories else {
            return
        }
        showsAllMemories = true
        for listener in showAllListeners.values {
            listener()
        }
    }

    /// 進行中のルームと思い出のきっぷを購読し、呼んだ `Task` が cancel されるまで続ける
    /// （cancel されたら、この呼び出しが始めたメンバー・当選した候補の購読も止める）
    func observe() async {
        async let active: Void = observeActiveRooms()
        async let memories: Void = observeClosedRooms()
        _ = await (active, memories)
    }

    /// 進行中のルームを購読し続ける（失敗したらトーストを 1 回出して読み直す）
    private func observeActiveRooms() async {
        var memberTasks: [String: Task<Void, Never>] = [:]
        defer {
            for task in memberTasks.values {
                task.cancel()
            }
        }
        var didShowFailure = false
        while !Task.isCancelled {
            for await update in repository.activeRooms(userID: userID) {
                // 画面が消えた後に流れ残りの値で戻さない
                guard !Task.isCancelled else {
                    break
                }
                switch update {
                case let .value(value):
                    apply(value, memberTasks: &memberTasks)
                    didShowFailure = false
                case let .failure(error):
                    guard !error.isCancellation, !didShowFailure else {
                        continue
                    }
                    toasts.show(text: error.message)
                    didShowFailure = true
                }
            }
            guard await resubscribeDelay.wait() else {
                break
            }
        }
    }

    /// 届いたルームの一覧を映し、メンバーの購読を一覧に合わせる（増えたルームは購読を始め、消えたルームは止めて捨てる）
    /// - Parameters:
    ///   - value: 届いた進行中のルーム
    ///   - memberTasks: この `observe()` が持つメンバーの購読（ルームの ID ごと）
    private func apply(_ value: [Identified<Room>], memberTasks: inout [String: Task<Void, Never>]) {
        rooms = value
        roomsState = .loaded
        let roomIDs = Set(value.map(\.id))
        for (roomID, task) in memberTasks where !roomIDs.contains(roomID) {
            task.cancel()
            memberTasks[roomID] = nil
            membersByRoom[roomID] = nil
        }
        for roomID in roomIDs where memberTasks[roomID] == nil {
            memberTasks[roomID] = Self.followMembers(
                of: roomID,
                repository: repository,
                resubscribeDelay: resubscribeDelay
            ) { [weak self] members in
                self?.membersByRoom[roomID] = members
            }
        }
    }

    /// 終了したルームの購読から届くもの
    private enum MemoriesEvent: Sendable {
        /// 終了したルームの一覧が届いた
        case rooms([Identified<Room>])
        /// 「すべて見る」が押された
        case showAll
    }

    /// 終了したルームを購読し続ける（失敗したらトーストを出さずに読み直す）。
    ///
    /// 「すべて見る」を押す前は `MemoryTicket.queryLimit` 件だけを読み、押されたら上限なしの購読に替える。
    /// 購読の値と「すべて見る」を 1 本のストリームにまとめ、この呼び出しの中で順に映す（当選した候補の購読をこの呼び出しが持つため）
    private func observeClosedRooms() async {
        let (events, continuation) = AsyncStream.makeStream(of: MemoriesEvent.self)
        let listenerID = UUID()
        showAllListeners[listenerID] = { continuation.yield(.showAll) }
        var winnerTasks: [String: Task<Void, Never>] = [:]
        var feed = followClosedRooms(limit: showsAllMemories ? nil : MemoryTicket.queryLimit, into: continuation)
        defer {
            showAllListeners[listenerID] = nil
            feed.cancel()
            continuation.finish()
            for task in winnerTasks.values {
                task.cancel()
            }
        }
        // 呼んだ Task が cancel されると、`for await` は次の値を待たずに終わる
        for await event in events {
            switch event {
            case let .rooms(value):
                applyClosed(value, winnerTasks: &winnerTasks)
            case .showAll:
                feed.cancel()
                feed = followClosedRooms(limit: nil, into: continuation)
                // 上限なしの一覧が届く前に、読んである 6 つ目のルームの当選した候補も購読し始める
                if memoriesState == .loaded {
                    applyClosed(closedRooms, winnerTasks: &winnerTasks)
                }
            }
        }
    }

    /// 終了したルームを `limit` 件まで購読し続ける `Task` を始め、届いた一覧を `continuation` に流す
    private func followClosedRooms(
        limit: Int?,
        into continuation: AsyncStream<MemoriesEvent>.Continuation
    ) -> Task<Void, Never> {
        let repository = repository
        let userID = userID
        return Self.follow(
            { repository.closedRooms(userID: userID, limit: limit) },
            resubscribeDelay: resubscribeDelay,
            onValue: { continuation.yield(.rooms($0)) }
        )
    }

    /// 届いた終了したルームを映し、当選した候補の購読を、きっぷを出すルーム（`MemoryTicket.watchedRooms`）に合わせる
    /// - Parameters:
    ///   - value: 届いた終了したルーム
    ///   - winnerTasks: この `observe()` が持つ当選した候補の購読（ルームの ID ごと）
    private func applyClosed(_ value: [Identified<Room>], winnerTasks: inout [String: Task<Void, Never>]) {
        closedRooms = value
        memoriesState = .loaded
        let watched = MemoryTicket.watchedRooms(value, showsAll: showsAllMemories)
        let winners = Dictionary(
            watched.compactMap { room in room.winnerCandidateId.map { (room.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for (roomID, task) in winnerTasks where winners[roomID] == nil {
            task.cancel()
            winnerTasks[roomID] = nil
            winnersByRoom[roomID] = nil
        }
        for (roomID, candidateID) in winners where winnerTasks[roomID] == nil {
            let repository = repository
            winnerTasks[roomID] = Self.follow(
                { repository.candidate(roomID: roomID, candidateID: candidateID) },
                resubscribeDelay: resubscribeDelay,
                onValue: { [weak self] candidate in
                    self?.winnersByRoom[roomID] = candidate?.value
                }
            )
        }
    }

    /// ルームのメンバーを購読し続ける `Task` を始める。失敗で終わったら、少し待って購読し直す（トーストは出さない）。
    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - repository: 購読の窓口
    ///   - resubscribeDelay: 購読し直すまでの待ち方
    ///   - onValue: メンバーが届いたときの処理
    private static func followMembers(
        of roomID: String,
        repository: any RoomRepository,
        resubscribeDelay: ResubscribeDelay,
        onValue: @escaping ([Identified<Member>]) -> Void
    ) -> Task<Void, Never> {
        follow({ repository.members(roomID: roomID) }, resubscribeDelay: resubscribeDelay, onValue: onValue)
    }

    /// 購読し続ける `Task` を始める。失敗で終わったら、少し待って購読し直す（トーストは出さない）。
    ///
    /// `Task` には self を渡さず、値が届いたときに `onValue`（self を弱く持つ）で映す。
    /// `self?.method()` の形で await すると、待っている間ずっと self を強く持ち、`[weak self]` が効かないため
    /// - Parameters:
    ///   - subscribe: 購読を始める（購読し直すたびに呼ぶ）
    ///   - resubscribeDelay: 購読し直すまでの待ち方
    ///   - onValue: 値が届いたときの処理
    private static func follow<Value: Sendable>(
        _ subscribe: @escaping () -> AsyncStream<LiveUpdate<Value>>,
        resubscribeDelay: ResubscribeDelay,
        onValue: @escaping (Value) -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                for await update in subscribe() {
                    // 一覧から消えて止めた後に、流れ残りの値で戻さない
                    guard !Task.isCancelled else {
                        return
                    }
                    if let value = update.value {
                        onValue(value)
                    }
                }
                guard await resubscribeDelay.wait() else {
                    return
                }
            }
        }
    }
}
