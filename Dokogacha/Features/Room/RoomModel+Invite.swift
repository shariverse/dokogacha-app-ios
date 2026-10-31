//
//  RoomModel+Invite.swift
//  Dokogacha
//

import Foundation

/// S-07 のアバターの並びの「＋」（招待）と、S-11 の「招待する」に出す値（02 の §2.4 F-04）
extension RoomModel {
    /// メンバーを招待できるか（`MemberInviteAvailability`）。
    ///
    /// ルームが届くまでと、招待コードが読めない（壊れた）ルームは `unavailable`（入口を出さない。招待のしようが無いため）。
    /// 人数はメンバーの購読の人数（`memberCount`）で数え、誰かが参加・退出すればそのまま変わる
    var inviteAvailability: MemberInviteAvailability {
        guard let room, InviteCode(room.inviteCode) != nil else {
            return .unavailable
        }
        return .of(status: room.status, memberCount: memberCount)
    }

    /// 招待の画面に渡すルーム（ルーム名と招待コード）。招待できないとき（満員を含む）は nil
    var inviteDestination: InviteDestination? {
        guard inviteAvailability == .available, let room, let code = InviteCode(room.inviteCode) else {
            return nil
        }
        return InviteDestination(roomID: roomID, roomName: room.name, inviteCode: code)
    }
}
