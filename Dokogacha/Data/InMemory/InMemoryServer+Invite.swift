//
//  InMemoryServer+Invite.swift
//  Dokogacha
//
//  擬似のサーバーの前回のメンバーへの招待（backend の `invite/service.ts` の `inviteLastMembers`）。
//  backend の `invite/logic.ts` と同じ順で検証し、同じ理由で失敗する（`InMemoryServerInviteTests` で確かめる）。
//  通知は送らず、送った相手を `lastMembersInvitations` に残す。
//

import Foundation

extension InMemoryServer {
    /// 前回のメンバーを今のルームに招待する（backend の `inviteLastMembers`）。呼んだ人の uid を `callerID` で受け取る。
    ///
    /// 入力の検証 → 今のルーム（無ければ `room-not-found`）→ メンバーか（`not-room-member`）→ 参加できる状態か
    /// （`open`・`unlocked`。違えば `room-already-decided`）の順に確かめる。前回のルーム（自分が参加した終了の日時がいちばん新しい
    /// `closed` のルーム）が無い・招待する人がいなければ 0 を返す。同じ今のルームから同じ前回のルームへの 2 回目は送らずに、1 回目の人数を返す
    /// （backend の印と同じく「今のルーム × 招待した人 × 前回のルーム」で 1 回。別の今のルームからは同じ前回のメンバーをまた招待できる）
    func inviteLastMembers(_ request: RoomRequest, by callerID: String?) throws -> InviteLastMembersResponse {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard let record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.memberIds.contains(userID) else {
            throw Self.error(.notRoomMember)
        }
        guard record.room.status == .open || record.room.status == .unlocked else {
            throw Self.error(.roomAlreadyDecided)
        }
        let closed = rooms.map { Identified(id: $0.key, value: $0.value.room) }
        guard let invitation = LastMembersInvitation.make(
            closedRooms: closed,
            currentMemberIDs: record.room.memberIds,
            userID: userID
        ) else {
            return InviteLastMembersResponse(invitedCount: 0)
        }
        let key = Self.lastMembersInvitationKey(roomID: roomID, userID: userID, sourceRoomID: invitation.sourceRoomID)
        if let sent = lastMembersInvitations[key] {
            return InviteLastMembersResponse(invitedCount: sent.count)
        }
        lastMembersInvitations[key] = invitation.inviteeIDs
        return InviteLastMembersResponse(invitedCount: invitation.count)
    }

    /// `lastMembersInvitations` の鍵（backend の `rooms/{今のルーム}/notificationLog/invited-{uid}-{前回のルーム}` と同じ単位）
    /// - Parameters:
    ///   - roomID: 今のルームの ID
    ///   - userID: 招待した人の uid
    ///   - sourceRoomID: 前回のルームの ID
    static func lastMembersInvitationKey(roomID: String, userID: String, sourceRoomID: String) -> String {
        "\(roomID)/invited-\(userID)-\(sourceRoomID)"
    }
}
