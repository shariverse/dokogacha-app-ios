//
//  InMemoryServer+Reroll.swift
//  Dokogacha
//
//  擬似のサーバーの引き直しの Callable（backend の `reroll/service.ts` の `proposeReroll`・`voteReroll`）と、
//  期限のスケジュール（`expireRerolls`）。backend の `reroll/logic.ts` と同じ順で検証し、同じ理由で失敗する
//  （`InMemoryServerRerollTests` で確かめる）。過半数の判定は `RerollRule`（backend の `domain/reroll.ts` と同じ式）。
//  提案の通知（`notifyRerollProposed`）は、backend でもまだログだけなので、ここでは何もしない。
//

import Foundation

extension InMemoryServer {
    /// この端末（サインインしている人）から引き直しを提案する（`FunctionsClient`）
    func proposeReroll(_ request: RoomRequest) async throws {
        try proposeReroll(request, by: signedInUserID)
    }

    /// この端末（サインインしている人）から引き直しに投票する（`FunctionsClient`）
    func voteReroll(_ request: VoteRerollRequest) async throws {
        try voteReroll(request, by: signedInUserID)
    }

    /// 引き直しを提案する（backend の `proposeReroll`。`drawn` のときだけ・ルームにつき 1 回・提案者は自動で賛成）。
    ///
    /// メンバーか → 終了していないか（`room-closed`）→ 投票中ならほかの人の提案に賛成として数える →
    /// 権利を使った後なら `reroll-used` → `drawn` でなければ `room-not-drawn` の順に確かめる。
    /// 提案者だけで過半数（1 人のルーム）ならその場で可決する
    func proposeReroll(_ request: RoomRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        try Self.assertRerollOpen(record.room, to: userID)
        let reroll = record.room.reroll
        if record.room.status == .drawn, reroll.status == .voting {
            Self.castVote(userID, approve: true, in: &record)
            rooms[roomID] = record
            return
        }
        guard !reroll.used, reroll.status == .notProposed else {
            throw Self.error(.rerollUsed)
        }
        guard record.room.status == .drawn else {
            throw Self.error(.roomNotDrawn)
        }
        record.room.reroll = RerollState(
            used: true, proposedBy: userID, proposedAt: clock(), votesFor: [userID], votesAgainst: [], status: .voting
        )
        Self.settleReroll(in: &record)
        rooms[roomID] = record
    }

    /// 引き直しに投票する（backend の `voteReroll`。賛成／反対。メンバーだけ・1 人 1 票・投票中は変えられる）。
    ///
    /// メンバーか → 終了していないか（`room-closed`）→ 投票中か（`drawn` で `voting`。でなければ `reroll-not-voting`）の順に確かめる
    func voteReroll(_ request: VoteRerollRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        try Self.assertRerollOpen(record.room, to: userID)
        guard record.room.status == .drawn, record.room.reroll.status == .voting else {
            throw Self.error(.rerollNotVoting)
        }
        Self.castVote(userID, approve: request.approve, in: &record)
        rooms[roomID] = record
    }

    /// 提案から 24 時間を過ぎた投票を否決にする（backend の `expireRerolls`。1 時間ごとのスケジュール）。
    ///
    /// 擬似のサーバーには時刻で動く仕組みが無いので、テスト・デモで時刻（`clock`）を進めた後に呼ぶ。
    /// 期限の時点で過半数（取りこぼした判定）なら可決にする（backend の `planExpiry` と同じ）
    /// - Returns: 否決にしたルームの数
    @discardableResult
    func expireRerolls() -> Int {
        let now = clock()
        var updated = rooms
        var rejected = 0
        for (roomID, record) in rooms {
            let reroll = record.room.reroll
            guard reroll.status == .voting else {
                continue
            }
            if let proposedAt = reroll.proposedAt, now.timeIntervalSince(proposedAt) < DomainConstants.Schedule.rerollVotingDuration {
                continue
            }
            var next = record
            Self.settleReroll(in: &next)
            if next.room.reroll.status != .passed || next.room.status != .unlocked {
                next = record
                next.room.reroll.status = .rejected
                rejected += 1
            }
            updated[roomID] = next
        }
        // 購読に 1 回だけ流すよう、まとめて入れ替える（変わっていなければ入れ替えない）
        if updated != rooms {
            rooms = updated
        }
        return rejected
    }

    /// 呼んだ人がメンバーで、ルームが終了していないか確かめる（提案と投票で共通。backend の `assertOpenToMember`）
    private static func assertRerollOpen(_ room: Room, to userID: String) throws {
        guard room.memberIds.contains(userID) else {
            throw error(.notRoomMember)
        }
        guard room.status != .closed else {
            throw error(.roomClosed)
        }
    }

    /// 1 人の票を入れ直し（前の票を取り除いてから、賛成か反対に入れる）、数え直す
    private static func castVote(_ userID: String, approve: Bool, in record: inout RoomRecord) {
        record.room.reroll.votesFor.removeAll { $0 == userID }
        record.room.reroll.votesAgainst.removeAll { $0 == userID }
        if approve {
            record.room.reroll.votesFor.append(userID)
        } else {
            record.room.reroll.votesAgainst.append(userID)
        }
        settleReroll(in: &record)
    }

    /// 投票中の票を数え直す（backend の `planOf`）。今のメンバーの票だけを重ねずに残し、賛成が過半数なら可決する:
    /// 直前の当選を除外リストに足し、ルームを `unlocked` に戻す（準備OKはやり直さない）。`drawn` で投票中でなければ何もしない
    static func settleReroll(in record: inout RoomRecord) {
        guard record.room.status == .drawn, record.room.reroll.status == .voting else {
            return
        }
        let members = Set(record.room.memberIds)
        func keep(_ uids: [String]) -> [String] {
            var seen = Set<String>()
            return uids.filter { members.contains($0) && seen.insert($0).inserted }
        }
        let votesFor = keep(record.room.reroll.votesFor)
        record.room.reroll.votesFor = votesFor
        record.room.reroll.votesAgainst = keep(record.room.reroll.votesAgainst).filter { !votesFor.contains($0) }
        let approvals = RerollRule.approvalCount(votesFor: votesFor, memberIds: record.room.memberIds)
        guard RerollRule.isMajority(approvals: approvals, memberCount: record.room.memberIds.count) else {
            return
        }
        record.room.reroll.status = .passed
        record.room.status = .unlocked
        if let winner = record.room.winnerCandidateId, !winner.isEmpty, !record.room.excludedCandidateIds.contains(winner) {
            record.room.excludedCandidateIds.append(winner)
        }
    }
}

extension InMemoryServer.Device {
    /// 引き直しを提案する（`proposeReroll`）
    func proposeReroll(_ request: RoomRequest) async throws {
        try server.proposeReroll(request, by: userID)
    }

    /// 引き直しに投票する（`voteReroll`）
    func voteReroll(_ request: VoteRerollRequest) async throws {
        try server.voteReroll(request, by: userID)
    }
}
