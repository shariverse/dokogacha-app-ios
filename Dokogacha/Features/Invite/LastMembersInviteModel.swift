//
//  LastMembersInviteModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-04 の「前回のメンバー（{前回ルーム名}・N人）を招待」（03 の S-04 の 4・02 の §2.4 F-04）の状態と操作。
///
/// 前回のルームと人数は、終了したルームの購読（`RoomRepository.closedRooms`。ホームの思い出のきっぷと同じクエリ）と、
/// 今のルームのメンバー（`room(id:)`）から、端末で決める（`LastMembersInvitation`）。前回のルームが無い・招待する人が 0 人なら
/// ボタンを出さない。画面（`InviteView`）は `.task` で `observe()` を呼び、画面が消えると cancel して購読を止める。
/// 購読の失敗はトーストを出さずに読み直す（ボタンが出ないだけで、招待コードとリンクは使える）。
///
/// 押すと Callable の `inviteLastMembers` を呼び、サーバーが決め直した人数でトースト「前回のメンバーN人に招待を送りました」を出す。
/// 送っている途中と送った後はボタンを押せなくする（同じ人たちに何度も送らない。サーバーも今のルームごとに、同じ前回のルームからは 1 回だけ送る）。
/// 失敗したら `AppError` の文言のトーストを出し、もう一度押せる。
@Observable
final class LastMembersInviteModel {
    /// 今のルームの ID
    let roomID: String
    /// 自分の uid
    let userID: String
    /// 届いた終了したルーム（まだ届いていなければ nil）
    private(set) var closedRooms: [Identified<Room>]?
    /// 今のルームのメンバー（届くまでは自分だけ）
    private(set) var currentMemberIDs: [String]
    /// `inviteLastMembers` を送っている途中か
    private(set) var isInviting = false
    /// 招待を送り終えたか（送った後はボタンを押せなくする）
    private(set) var hasInvited = false

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// 押して始めた招待（二重に始めないために持つ）
    @ObservationIgnored private var inviteTask: Task<Void, Never>?

    /// - Parameters:
    ///   - roomID: 今のルームの ID
    ///   - userID: 自分の uid
    ///   - repository: 終了したルームと今のルームの購読の窓口
    ///   - functions: `inviteLastMembers` を呼ぶ窓口
    ///   - toasts: 結果を出すトーストの窓口
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.roomID = roomID
        self.userID = userID
        self.repository = repository
        self.functions = functions
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
        currentMemberIDs = [userID]
    }

    /// ボタンに出す前回のルームと人数（無ければボタンを出さない）
    var invitation: LastMembersInvitation? {
        guard let closedRooms else {
            return nil
        }
        return LastMembersInvitation.make(closedRooms: closedRooms, currentMemberIDs: currentMemberIDs, userID: userID)
    }

    /// ボタンを押せるか
    var canInvite: Bool {
        invitation != nil && !isInviting && !hasInvited
    }

    /// 終了したルームと今のルームを購読し、呼んだ `Task` が cancel されるまで続ける
    func observe() async {
        async let closed: Void = observeClosedRooms()
        async let current: Void = observeCurrentRoom()
        _ = await (closed, current)
    }

    /// ボタンが押された。招待を始める（始めた Task が残っている間・送った後は受け付けない）。
    /// 画面が消えても送ったものは止めない（押した時点で送ると決めたので送り切る）
    func inviteTapped() {
        guard inviteTask == nil, canInvite else {
            return
        }
        inviteTask = Task { [weak self] in
            await self?.invite()
            self?.inviteTask = nil
        }
    }

    /// 前回のメンバーを招待する（`inviteLastMembers`）。結果をトーストで出す
    func invite() async {
        guard canInvite else {
            return
        }
        isInviting = true
        defer { isInviting = false }
        do {
            let response = try await functions.inviteLastMembers(RoomRequest(roomId: roomID))
            hasInvited = true
            if response.invitedCount > 0 {
                toasts.show(text: String(localized: "前回のメンバー\(response.invitedCount)人に招待を送りました"))
            } else {
                // 押した後に前回のメンバーが参加した・前回のルームが変わったなど、サーバーで 0 人になったとき
                toasts.show(text: String(localized: "招待できる前回のメンバーがいません"))
            }
        } catch {
            toasts.showFailure(error)
        }
    }

    /// 終了したルームを購読し続ける（失敗したらトーストを出さずに読み直す）。
    ///
    /// 前回のルームは直近の 1 件だけなので、終了した日時の新しい順に 1 件だけ読む
    private func observeClosedRooms() async {
        while !Task.isCancelled {
            for await update in repository.closedRooms(userID: userID, limit: 1) {
                guard !Task.isCancelled else {
                    break
                }
                if let rooms = update.value {
                    closedRooms = rooms
                }
            }
            guard await resubscribeDelay.wait() else {
                break
            }
        }
    }

    /// 今のルームのメンバーを購読し続ける（失敗したらトーストを出さずに読み直す。届くまでは自分だけとして数える）
    private func observeCurrentRoom() async {
        while !Task.isCancelled {
            for await update in repository.room(id: roomID) {
                guard !Task.isCancelled else {
                    break
                }
                if case let .value(room?) = update {
                    currentMemberIDs = room.memberIds
                }
            }
            guard await resubscribeDelay.wait() else {
                break
            }
        }
    }
}
