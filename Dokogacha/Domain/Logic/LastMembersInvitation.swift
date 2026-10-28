//
//  LastMembersInvitation.swift
//  Dokogacha
//

import Foundation

/// S-04 の「前回のメンバー（{前回ルーム名}・N人）を招待」に出す前回のルームと人数（02 の §2.4 F-04「前回のメンバーを招待」）。
///
/// 前回のルームは、自分が参加した終了したルーム（`closed`）のうち、終了の日時がいちばん新しいもの
/// （backend の `inviteLastMembers` が `closedAt` の降順で 1 件を選ぶのと同じ。ホームの思い出のきっぷの購読から選ぶ）。
/// 招待する人は、そのルームの終了したときのメンバーから、自分と今のルームにもういる人を外した人
/// （backend の `invite/logic.ts` の `lastMembersInvitees` と同じ規則。片方を変えたら両方を変える）。
/// 実際に送る人と人数はサーバーが決め直す（ボタンの人数は表示のため）。
nonisolated struct LastMembersInvitation: Equatable, Sendable {
    /// 前回のルームの ID
    let sourceRoomID: String
    /// 前回のルームの名前
    let sourceRoomName: String
    /// 招待する人の uid（前回のルームの参加の順）
    let inviteeIDs: [String]

    /// 招待する人数
    var count: Int {
        inviteeIDs.count
    }

    /// 終了したルームから、前回のルームと招待する人を決める。
    ///
    /// 前回のルームが無い・招待する人が 0 人（前回が自分だけ・全員がもう今のルームにいる）なら nil（ボタンを出さない。03 の S-04
    /// 「前回ルームがあるときだけ表示」。押しても誰にも届かないボタンは出さない）
    /// - Parameters:
    ///   - closedRooms: 自分が参加した終了したルーム（並びは問わない）
    ///   - currentMemberIDs: 今のルームのメンバー
    ///   - userID: 自分の uid
    static func make(closedRooms: [Identified<Room>], currentMemberIDs: [String], userID: String) -> Self? {
        let latest = closedRooms
            .filter { $0.status == .closed && $0.memberIds.contains(userID) }
            .max { ($0.closedAt ?? .distantPast, $0.id) < ($1.closedAt ?? .distantPast, $1.id) }
        guard let latest else {
            return nil
        }
        let invitees = invitees(previousMemberIDs: latest.memberIds, currentMemberIDs: currentMemberIDs, userID: userID)
        guard !invitees.isEmpty else {
            return nil
        }
        return Self(sourceRoomID: latest.id, sourceRoomName: latest.name, inviteeIDs: invitees)
    }

    /// 招待する人（前回のメンバーから、自分と今のメンバーを外す。同じ人は 1 回だけ。前回の並びを保つ）
    /// - Parameters:
    ///   - previousMemberIDs: 前回のルームのメンバー
    ///   - currentMemberIDs: 今のルームのメンバー
    ///   - userID: 自分の uid
    static func invitees(previousMemberIDs: [String], currentMemberIDs: [String], userID: String) -> [String] {
        var skipped = Set(currentMemberIDs)
        skipped.insert(userID)
        var result: [String] = []
        for memberID in previousMemberIDs where !skipped.contains(memberID) {
            skipped.insert(memberID)
            result.append(memberID)
        }
        return result
    }
}
