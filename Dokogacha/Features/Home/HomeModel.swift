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
/// 「思い出のきっぷ」（`closed` のルーム）の購読はタスク 30 で足す。いまは空の表示だけ。
@Observable
final class HomeModel {
    /// 進行中のルームの読み込みの状態
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

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay

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

    /// 進行中のルームを購読し、呼んだ `Task` が cancel されるまで続ける（cancel されたら、この呼び出しが始めたメンバーの購読も止める）
    func observe() async {
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

    /// ルームのメンバーを購読し続ける `Task` を始める。失敗で終わったら、少し待って購読し直す（トーストは出さない）。
    ///
    /// `Task` には self を渡さず、値が届いたときに `onValue`（self を弱く持つ）で映す。
    /// `self?.method()` の形で await すると、待っている間ずっと self を強く持ち、`[weak self]` が効かないため
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
        Task {
            while !Task.isCancelled {
                for await update in repository.members(roomID: roomID) {
                    // 一覧から消えて止めた後に、流れ残りの値で戻さない
                    guard !Task.isCancelled else {
                        return
                    }
                    if let members = update.value {
                        onValue(members)
                    }
                }
                guard await resubscribeDelay.wait() else {
                    return
                }
            }
        }
    }
}
