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
    /// ルームごとのメンバーの購読（並んでいるルームの分だけ持つ）
    @ObservationIgnored private var memberTasks: [String: Task<Void, Never>] = [:]

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

    deinit {
        for task in memberTasks.values {
            task.cancel()
        }
    }

    /// 進行中のルームのカード（作成日時の新しい順）
    var cards: [HomeRoomCard] {
        HomeRoomCard.cards(rooms: rooms, members: membersByRoom)
    }

    /// 進行中のルームが 1 つも無いと分かったか（空の表示を出す）
    var isEmpty: Bool {
        roomsState == .loaded && cards.isEmpty
    }

    /// 進行中のルームを購読し、呼んだ `Task` が cancel されるまで続ける（cancel されたらメンバーの購読も止める）
    func observe() async {
        var didShowFailure = false
        while !Task.isCancelled {
            for await update in repository.activeRooms(userID: userID) {
                switch update {
                case let .value(value):
                    apply(value)
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
        stopAllMemberSubscriptions()
    }

    /// 届いたルームの一覧を映し、メンバーの購読を一覧に合わせる（増えたルームは購読を始め、消えたルームは止めて捨てる）
    private func apply(_ value: [Identified<Room>]) {
        rooms = value
        roomsState = .loaded
        let roomIDs = Set(value.map(\.id))
        for (roomID, task) in memberTasks where !roomIDs.contains(roomID) {
            task.cancel()
            memberTasks[roomID] = nil
            membersByRoom[roomID] = nil
        }
        for roomID in roomIDs where memberTasks[roomID] == nil {
            memberTasks[roomID] = Task { [weak self] in
                await self?.followMembers(of: roomID)
            }
        }
    }

    /// ルームのメンバーを購読し続ける。失敗で終わったら、少し待って購読し直す（トーストは出さない）
    private func followMembers(of roomID: String) async {
        while !Task.isCancelled {
            for await update in repository.members(roomID: roomID) {
                // 一覧から消えて止めた後に、流れ残りの値で戻さない
                if let members = update.value, !Task.isCancelled {
                    membersByRoom[roomID] = members
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
    }

    /// メンバーの購読をすべて止める
    private func stopAllMemberSubscriptions() {
        for task in memberTasks.values {
            task.cancel()
        }
        memberTasks = [:]
    }
}
