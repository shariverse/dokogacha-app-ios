//
//  InMemoryServerRerollTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `proposeReroll`・`voteReroll`・`expireRerolls` が、backend と同じ検証・状態遷移をすることを確かめる
/// （backend の `test/emulator/reroll.test.ts`・`reroll/logic.test.ts` と同じ観点）
struct InMemoryServerRerollTests {
    /// 時刻を進められる時計
    final class Clock {
        var now = InMemoryServerDrawTests.now
    }

    /// "owner"・"bob"・"carol" のルームで、owner が回して最初の候補（いいね 2）が当たった状態
    static func drawnRoom(_ server: InMemoryServer) async throws -> (roomID: String, candidates: [String]) {
        let (roomID, candidates) = try await InMemoryServerDrawTests.makeRoom(server)
        let response = try await server.drawGacha(RoomRequest(roomId: roomID))
        #expect(response.candidateId == candidates[0])
        return (roomID, candidates)
    }

    /// 提案すると、権利を使って投票中になり、提案者は自動で賛成（3 人で 1 票はまだ過半数でない）
    @Test
    func proposeStartsVoting() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (roomID, _) = try await Self.drawnRoom(server)
        try await server.device(of: "bob").proposeReroll(RoomRequest(roomId: roomID))
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.status == .drawn)
        #expect(room.reroll == RerollState(
            used: true, proposedBy: "bob", proposedAt: InMemoryServerDrawTests.now, votesFor: ["bob"], votesAgainst: [], status: .voting
        ))
    }

    /// F-43 の AC: 可決すると前回の当選候補は次の抽選の対象から外れる（同じ乱数でも当たらない）。準備OKはやり直さない。2 回目は提案できない
    @Test
    func passExcludesPreviousWinnerFromNextDraw() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (roomID, candidates) = try await Self.drawnRoom(server)
        try await server.proposeReroll(RoomRequest(roomId: roomID))
        try await server.device(of: "bob").voteReroll(VoteRerollRequest(roomId: roomID, approve: true))

        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.status == .unlocked)
        #expect(room.excludedCandidateIds == [candidates[0]])
        #expect(room.reroll.status == .passed)
        #expect(room.readyCount == 3)
        #expect(server.rooms[roomID]?.members.values.allSatisfy(\.ready) == true)

        let next = try await server.device(of: "carol").drawGacha(RoomRequest(roomId: roomID))
        #expect(next.candidateId == candidates[1])
        let draw = try #require(server.rooms[roomID]?.draws[next.drawId])
        #expect(draw.isReroll)
        #expect(draw.weights[candidates[0]] == nil)

        await #expect(throws: InMemoryServer.error(.rerollUsed)) {
            try await server.proposeReroll(RoomRequest(roomId: roomID))
        }
    }

    /// 1 人 1 票: 票を変えると前の票を取り除き、同じ票をもう一度送っても数は変わらない。全員が投票しても期限までは否決にしない
    @Test
    func votesCanBeChanged() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (roomID, _) = try await Self.drawnRoom(server)
        try await server.proposeReroll(RoomRequest(roomId: roomID))
        let bob = server.device(of: "bob")
        try await bob.voteReroll(VoteRerollRequest(roomId: roomID, approve: false))
        try await bob.voteReroll(VoteRerollRequest(roomId: roomID, approve: false))
        try await server.device(of: "carol").voteReroll(VoteRerollRequest(roomId: roomID, approve: false))
        var reroll = try #require(server.rooms[roomID]?.room.reroll)
        #expect(reroll.votesFor == ["owner"])
        #expect(reroll.votesAgainst == ["bob", "carol"])
        #expect(reroll.status == .voting)

        try await bob.voteReroll(VoteRerollRequest(roomId: roomID, approve: true))
        reroll = try #require(server.rooms[roomID]?.room.reroll)
        #expect(reroll.votesFor == ["owner", "bob"])
        #expect(reroll.votesAgainst == ["carol"])
        #expect(reroll.status == .passed)
    }

    /// ほかの人が先に提案して投票中なら、提案の代わりに賛成の票として数える（同時に押した）
    @Test
    func secondProposalCountsAsApproval() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (roomID, _) = try await Self.drawnRoom(server)
        try await server.device(of: "bob").proposeReroll(RoomRequest(roomId: roomID))
        try await server.device(of: "carol").proposeReroll(RoomRequest(roomId: roomID))
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.reroll.proposedBy == "bob")
        #expect(room.reroll.votesFor == ["bob", "carol"])
        #expect(room.status == .unlocked)
    }

    /// メンバーでない・ルームが無い・行き先が決まる前・終了後・投票中でないときは、backend と同じ理由で断る
    @Test
    func rejectsInvalidRequests() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (openRoomID, _) = try await InMemoryServerDrawTests.makeRoom(server, ready: ["owner"])
        await #expect(throws: InMemoryServer.error(.roomNotDrawn)) {
            try await server.proposeReroll(RoomRequest(roomId: openRoomID))
        }
        let (roomID, _) = try await Self.drawnRoom(server)
        await #expect(throws: InMemoryServer.error(.notRoomMember)) {
            try await server.device(of: "mallory").proposeReroll(RoomRequest(roomId: roomID))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.proposeReroll(RoomRequest(roomId: "missing"))
        }
        await #expect(throws: InMemoryServer.error(.rerollNotVoting)) {
            try await server.voteReroll(VoteRerollRequest(roomId: roomID, approve: true))
        }
        server.rooms[roomID]?.room.status = .closed
        await #expect(throws: InMemoryServer.error(.roomClosed)) {
            try await server.proposeReroll(RoomRequest(roomId: roomID))
        }
        #expect(server.rooms[roomID]?.room.reroll == .initial)
    }

    /// 投票中にメンバーが外れると、残りのメンバーで判定し直す（賛成 1 / 3 人 → 退出で 1 / 2 人はまだ投票中 → 削除で 1 / 1 人は可決）
    @Test
    func leavingRejudgesVote() async throws {
        let server = InMemoryServerDrawTests.makeServer()
        let (roomID, candidates) = try await Self.drawnRoom(server)
        try await server.proposeReroll(RoomRequest(roomId: roomID))
        try await server.device(of: "bob").leaveRoom(RoomRequest(roomId: roomID))
        #expect(server.rooms[roomID]?.room.status == .drawn)
        try await server.removeMember(RemoveMemberRequest(roomId: roomID, memberId: "carol"))
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.status == .unlocked)
        #expect(room.reroll.status == .passed)
        #expect(room.excludedCandidateIds == [candidates[0]])
    }

    /// 提案から 24 時間を過ぎた投票だけを否決にし、権利は使ったまま（06 の §4 の仮決め）
    @Test
    func expiresAfterVotingDuration() async throws {
        let clock = Clock()
        let base = InMemoryServerDrawTests.makeServer()
        let server = InMemoryServer(
            clock: { clock.now }, randomIndex: base.randomIndex, makeID: base.makeID, signedInUserID: "owner"
        )
        let (roomID, _) = try await Self.drawnRoom(server)
        try await server.proposeReroll(RoomRequest(roomId: roomID))

        clock.now = InMemoryServerDrawTests.now.addingTimeInterval(DomainConstants.Schedule.rerollVotingDuration - 1)
        #expect(server.expireRerolls() == 0)
        #expect(server.rooms[roomID]?.room.reroll.status == .voting)

        clock.now = InMemoryServerDrawTests.now.addingTimeInterval(DomainConstants.Schedule.rerollVotingDuration)
        #expect(server.expireRerolls() == 1)
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.status == .drawn)
        #expect(room.reroll.status == .rejected)
        #expect(room.reroll.used)
        #expect(room.excludedCandidateIds.isEmpty)
        await #expect(throws: InMemoryServer.error(.rerollUsed)) {
            try await server.device(of: "bob").proposeReroll(RoomRequest(roomId: roomID))
        }
        await #expect(throws: InMemoryServer.error(.rerollNotVoting)) {
            try await server.device(of: "bob").voteReroll(VoteRerollRequest(roomId: roomID, approve: true))
        }
    }
}
