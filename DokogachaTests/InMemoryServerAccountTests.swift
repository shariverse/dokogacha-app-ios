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

    /// 抽選の前の作成者のルーム（当選が無い）は、アカウントの削除で終了しても過去のアイデアを登録しない
    /// （backend の account の Emulator のテストと同じ。Discussion #155 の Q4）
    @Test
    func closingOwnRoomBeforeDrawRegistersNoPastIdeas() throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        server.rooms[DemoScenario.drawnRoomID]?.room.status = .unlocked
        server.rooms[DemoScenario.drawnRoomID]?.room.currentDrawId = nil
        server.rooms[DemoScenario.drawnRoomID]?.room.winnerCandidateId = nil

        try server.deleteAccount(by: DemoScenario.myUserID)

        #expect(server.rooms[DemoScenario.drawnRoomID]?.room.status == .closed)
        #expect(server.pastIdeas[Self.haruka]?["\(DemoScenario.drawnRoomID)_drawn-mine-2"] == nil)
        #expect(server.pastIdeas.values.allSatisfy { ideas in ideas.values.allSatisfy { $0.sourceRoomId != DemoScenario.drawnRoomID } })
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

    /// 削除した後は、サインインしたまま残った uid が消えていると分かる（Firebase の `reload` の userNotFound の代わり）。削除の前・ほかの人は消えていない
    @Test
    func reportsDeletedCurrentAccount() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        #expect(await !server.isCurrentAccountDeleted())
        try server.deleteAccount(by: Self.haruka)
        #expect(await !server.isCurrentAccountDeleted())
        try await server.deleteAccount()
        #expect(await server.isCurrentAccountDeleted())
        server.signOut()
        #expect(await !server.isCurrentAccountDeleted())
    }

    /// Apple のトークンの取り消しは、渡された authorization code を記録する（サインインしていなければ unauthenticated）
    @Test
    func revokesAppleTokenWhenSignedIn() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        try await server.revokeAppleToken(authorizationCode: "code-1")
        #expect(server.revokedAppleAuthorizationCodes == ["code-1"])
        server.signOut()
        await #expect(throws: InMemoryServer.error(.unauthenticated)) {
            try await server.revokeAppleToken(authorizationCode: "code-2")
        }
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

        try server.closeRoom(CloseRoomRequest(roomId: DemoScenario.drawnRoomID, reason: .decide), by: DemoScenario.myUserID)

        #expect(server.pastIdeas[Self.sota] == nil)
        #expect(server.pastIdeas[Self.haruka]?.count == 2)
        #expect(server.pastIdeas[DemoScenario.myUserID]?.count == 2)
    }
}
