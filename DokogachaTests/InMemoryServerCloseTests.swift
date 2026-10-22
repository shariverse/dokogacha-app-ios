//
//  InMemoryServerCloseTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーのルームの終了（`closeRoom`）が、backend の `close/logic.ts`・`close/service.ts` と同じ順で検証し、
/// 終了したら過去のアイデアを登録すること（Emulator のテスト `test/emulator/close.test.ts` と同じ観点）。
///
/// デモのルームは `drawn-rooms` の「週末のランチ」（自分が作成者・はるか・そうた。サンシャイン水族館が当選、候補 3 件）
struct InMemoryServerCloseTests {
    static let roomID = DemoScenario.drawnRoomID
    static let haruka = "demo-haruka"

    static func makeServer() -> InMemoryServer {
        InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
    }

    /// サーバーのエラーの理由で失敗することを確かめる
    static func expectReason(_ reason: AppError.Reason, _ body: () throws -> Void) {
        #expect {
            try body()
        } throws: { error in
            (error as? AppError)?.reason == reason
        }
    }

    /// 作成者が drawn のルームを closed にし、当選以外の候補を全員の過去のアイデアに登録する
    @Test
    func ownerClosesDrawnRoomAndRegistersPastIdeas() throws {
        let server = Self.makeServer()
        try server.closeRoom(RoomRequest(roomId: Self.roomID), by: DemoScenario.myUserID)

        let room = try #require(server.rooms[Self.roomID]?.room)
        #expect(room.status == .closed)
        #expect(room.closedAt == RoomModelTests.now)
        for userID in [DemoScenario.myUserID, Self.haruka, "demo-sota"] {
            let ideas = try #require(server.pastIdeas[userID])
            #expect(ideas.keys.sorted() == ["\(Self.roomID)_drawn-mine-2", "\(Self.roomID)_drawn-mine-3"])
            #expect(ideas.values.allSatisfy { $0.sourceWinnerName == "サンシャイン水族館" && $0.sourceRoomName == "週末のランチ" })
        }
        #expect(server.pastIdeas["demo-mio"] == nil)
        #expect(server.pastIdeas[DemoScenario.myUserID]?["\(Self.roomID)_drawn-mine-3"]?.prevLikeCount == 1)
    }

    /// もう closed なら何もしない（終了の日時を書き換えない）
    @Test
    func closingTwiceDoesNothing() throws {
        var now = RoomModelTests.now
        let server = InMemoryServer.demo(.drawnRooms) { now }
        try server.closeRoom(RoomRequest(roomId: Self.roomID), by: DemoScenario.myUserID)
        now = now.addingTimeInterval(60)
        try server.closeRoom(RoomRequest(roomId: Self.roomID), by: DemoScenario.myUserID)
        #expect(server.rooms[Self.roomID]?.room.closedAt == RoomModelTests.now)
    }

    /// 引き直しの投票中でも終了でき、同時に投票を否決にする（票は残す）。期限を過ぎても `expireRerolls` は終了したルームを書き換えない
    @Test
    func closingWhileRerollVotingRejectsTheVote() throws {
        var now = RoomModelTests.now
        let server = InMemoryServer.demo(.drawnRooms) { now }
        try server.proposeReroll(RoomRequest(roomId: Self.roomID), by: Self.haruka)
        #expect(server.rooms[Self.roomID]?.room.reroll.status == .voting)

        try server.closeRoom(RoomRequest(roomId: Self.roomID), by: DemoScenario.myUserID)
        let closed = try #require(server.rooms[Self.roomID]?.room)
        #expect(closed.status == .closed)
        #expect(closed.reroll.status == .rejected)
        #expect(closed.reroll.used)
        #expect(closed.reroll.votesFor == [Self.haruka])

        now = now.addingTimeInterval(DomainConstants.Schedule.rerollVotingDuration * 2)
        #expect(server.expireRerolls() == 0)
        #expect(server.rooms[Self.roomID]?.room == closed)
    }

    /// 作成者以外は not-room-owner・メンバー以外は not-room-member・行き先が決まる前は room-not-drawn・無いルームは room-not-found
    @Test
    func rejectsInTheSameOrderAsBackend() throws {
        let server = Self.makeServer()
        Self.expectReason(.notRoomOwner) { try server.closeRoom(RoomRequest(roomId: Self.roomID), by: Self.haruka) }
        Self.expectReason(.notRoomMember) { try server.closeRoom(RoomRequest(roomId: Self.roomID), by: "demo-mio") }
        Self.expectReason(.roomNotFound) { try server.closeRoom(RoomRequest(roomId: "nothing"), by: DemoScenario.myUserID) }
        Self.expectReason(.invalidArgument) { try server.closeRoom(RoomRequest(roomId: "a/b"), by: DemoScenario.myUserID) }
        Self.expectReason(.unauthenticated) { try server.closeRoom(RoomRequest(roomId: Self.roomID), by: nil) }
        #expect(server.rooms[Self.roomID]?.room.status == .drawn)

        server.rooms[Self.roomID]?.room.status = .unlocked
        Self.expectReason(.roomNotDrawn) { try server.closeRoom(RoomRequest(roomId: Self.roomID), by: DemoScenario.myUserID) }
        #expect(server.pastIdeas.isEmpty)
    }

    /// 終了したルームは、ホームの思い出のきっぷの購読に、終了の新しい順で流れる。当選した候補 1 件も購読できる
    @Test
    func closedRoomsAreSubscribable() async throws {
        let server = InMemoryServer.demo(.memories) { RoomModelTests.now }
        var closed = server.closedRooms(userID: DemoScenario.myUserID, limit: nil).makeAsyncIterator()
        let first = try #require(await closed.next()?.value)
        #expect(first.count == 6)
        #expect(first.map(\.id) == (1...6).map { "\(DemoScenario.closedRoomIDPrefix)\($0)" })

        var winner = server.candidate(roomID: Self.roomID, candidateID: "drawn-mine-1").makeAsyncIterator()
        let candidate = try #require(await winner.next()?.value)
        #expect(candidate?.place.name == "サンシャイン水族館")

        // メンバーでないルームの候補は読めない（ルールと同じ）
        server.rooms[Self.roomID]?.room.memberIds = [Self.haruka]
        var denied = server.candidate(roomID: Self.roomID, candidateID: "drawn-mine-1").makeAsyncIterator()
        #expect(await denied.next()?.error?.isPermissionDenied == true)
    }
}
