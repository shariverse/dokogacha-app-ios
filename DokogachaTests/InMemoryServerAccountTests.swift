//
//  InMemoryServerAccountTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーのアカウントの削除（`deleteAccount`）が、backend の `account/service.ts` と同じことをすること
/// （Emulator のテスト `test/emulator/account.test.ts` と同じ観点）
struct InMemoryServerAccountTests {
    static let haruka = "demo-haruka"
    static let sota = "demo-sota"

    /// メンバーのルームからは退出と同じに外れる（いいねの取り消し・購入者の付け替え）。投稿した候補は残り、プロフィールは消える
    @Test
    func memberLeavesRoomAndKeepsCandidates() throws {
        let server = InMemoryServer.demo(.adFreeRoom)
        #expect(server.rooms[DemoScenario.roomID]?.room.adFreeSponsor?.uid == Self.haruka)

        try server.deleteAccount(by: Self.haruka)

        let record = try #require(server.rooms[DemoScenario.roomID])
        #expect(record.room.status == .open)
        #expect(!record.room.memberIds.contains(Self.haruka))
        #expect(record.members[Self.haruka] == nil)
        #expect(record.room.memberCount == record.members.count)
        // ほかに購入者がいないので、広告なしではなくなる
        #expect(record.room.adFreeSponsor == nil)
        // 投稿した候補は「退出したメンバー」の投稿として残り、付けたいいねは取り消される
        #expect(record.candidates["demo-candidate-1"]?.postedBy == Self.haruka)
        #expect(record.candidates["demo-candidate-1"]?.postedByName == "はるか")
        #expect(record.candidates["demo-candidate-3"]?.likedBy.isEmpty == true)
        #expect(server.users[Self.haruka] == nil)
        #expect(server.users[DemoScenario.myUserID] != nil)
    }

    /// 作成者のルームは終了して作成者を外し、過去のアイデアは残るメンバーにだけ登録する。ほかの人のルームからは外れるだけ。
    /// この端末のサインインはそのまま（アプリが `signOut` で外す）
    @Test
    func ownerClosesOwnRoomAndLeavesOthers() async throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let oldIdea = try #require(InMemoryServer.demo(.pastIdeas).pastIdeas[DemoScenario.myUserID]?.values.first)
        server.pastIdeas[DemoScenario.myUserID] = ["old_c1": oldIdea]

        try await server.deleteAccount()

        let mine = try #require(server.rooms[DemoScenario.drawnRoomID]?.room)
        #expect(mine.status == .closed)
        #expect(mine.closedAt == RoomModelTests.now)
        #expect(mine.ownerId == DemoScenario.myUserID)
        #expect(mine.memberIds == [Self.haruka, Self.sota])
        let expected = ["\(DemoScenario.drawnRoomID)_drawn-mine-2", "\(DemoScenario.drawnRoomID)_drawn-mine-3"]
        #expect(server.pastIdeas[Self.haruka]?.keys.sorted() == expected)
        #expect(server.pastIdeas[Self.sota]?.keys.sorted() == expected)
        #expect(server.pastIdeas[DemoScenario.myUserID] == nil)
        // 自分の投稿は残る
        #expect(server.rooms[DemoScenario.drawnRoomID]?.candidates["drawn-mine-3"]?.postedBy == DemoScenario.myUserID)

        let others = try #require(server.rooms[DemoScenario.othersDrawnRoomID]?.room)
        #expect(others.status == .drawn)
        #expect(!others.memberIds.contains(DemoScenario.myUserID))
        #expect(server.users[DemoScenario.myUserID] == nil)
        #expect(server.signedInUserID == DemoScenario.myUserID)
        server.signOut()
        #expect(server.signedInUserID == nil)
    }

    /// 作成者のルームで引き直しの投票中なら、終了と同時に否決にする（`expireRerolls` が終了したルームを後から書き換えない）
    @Test
    func closingOwnRoomRejectsVotingReroll() throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        try server.proposeReroll(RoomRequest(roomId: DemoScenario.drawnRoomID), by: Self.haruka)
        #expect(server.rooms[DemoScenario.drawnRoomID]?.room.reroll.status == .voting)

        try server.deleteAccount(by: DemoScenario.myUserID)

        let room = try #require(server.rooms[DemoScenario.drawnRoomID]?.room)
        #expect(room.status == .closed)
        #expect(room.reroll.status == .rejected)
        #expect(room.excludedCandidateIds.isEmpty)
    }

    /// 何度呼んでも同じ結果になる。Sign in with Apple の連携も外れる
    @Test
    func deletingTwiceIsIdempotentAndUnlinksApple() throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        server.appleAccounts["apple-account"] = DemoScenario.myUserID
        server.appleAccounts["apple-other"] = Self.haruka

        try server.deleteAccount(by: DemoScenario.myUserID)
        let rooms = server.rooms
        let ideas = server.pastIdeas
        try server.deleteAccount(by: DemoScenario.myUserID)
        #expect(server.rooms == rooms)
        #expect(server.pastIdeas == ideas)
        #expect(server.appleAccounts == ["apple-other": Self.haruka])
        #expect(!server.isLinkedWithApple)
    }

    /// サインインしていなければ unauthenticated
    @Test
    func requiresSignIn() async {
        let server = InMemoryServer.demo(.oneRoom)
        server.signedInUserID = nil
        await #expect(throws: InMemoryServer.error(.unauthenticated)) {
            try await server.deleteAccount()
        }
    }

    /// 終了の後の過去のアイデアの登録は、アカウントを削除した人（`users/{uid}` が無い）を飛ばす（backend の `registerPastIdeas`）
    @Test
    func pastIdeasSkipDeletedUsers() throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        server.users[Self.sota] = nil

        try server.closeRoom(RoomRequest(roomId: DemoScenario.drawnRoomID), by: DemoScenario.myUserID)

        #expect(server.pastIdeas[Self.sota] == nil)
        #expect(server.pastIdeas[Self.haruka]?.count == 2)
        #expect(server.pastIdeas[DemoScenario.myUserID]?.count == 2)
    }
}
