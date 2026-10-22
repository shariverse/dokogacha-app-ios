//
//  InMemoryAutoMembersTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// UI テストの、ほかのメンバーの操作を自動で返す仕組み（`InMemoryAutoMembers`・`-ui-auto-members`）を確かめる。
///
/// 返すのは購読の Task なので、固定の時間ではなく `AsyncTestSupport.eventually` で状態が変わるのを待つ
@Suite(.timeLimit(.minutes(1)))
struct InMemoryAutoMembersTests {
    /// 自分が作ったルームに自分しかいなければ、はるかが招待コードで参加して候補を 1 件投稿する。
    /// はるかのプロフィールが無い（初回起動の）シナリオでは、参加の前に表示名を登録する
    @Test
    func joinerJoinsAndPostsWhenOwnerIsAlone() async throws {
        let server = InMemoryServer.demo(.firstLaunch)
        let autoMembers = InMemoryAutoMembers(server: server)
        _ = try await server.saveDisplayName("たくみ")
        let created = try await server.createRoom(
            CreateRoomRequest(name: "年末の旅行", postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost)
        )

        let joiner = InMemoryAutoMembers.joinerID
        #expect(await AsyncTestSupport.eventually {
            server.rooms[created.roomId]?.candidates.isEmpty == false
        })
        let record = try #require(server.rooms[created.roomId])
        #expect(record.room.memberIds == [DemoScenario.myUserID, joiner])
        #expect(record.members[joiner]?.displayName == InMemoryAutoMembers.joinerName)
        #expect(record.candidates.values.map(\.place.name) == ["明治神宮"])
        #expect(record.candidates.values.map(\.postedBy) == [joiner])
        withExtendedLifetime(autoMembers) {}
    }

    /// ほかのメンバーがいるルームには参加しない（デモのデータのルームを変えない）
    @Test
    func joinerDoesNotJoinRoomWithMembers() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        let autoMembers = InMemoryAutoMembers(server: server)
        let before = try #require(server.rooms[DemoScenario.roomID])
        await InMemoryAutoMembers.respond(on: server)
        #expect(server.rooms[DemoScenario.roomID] == before)
        withExtendedLifetime(autoMembers) {}
    }

    /// 自分が準備OKにすると、ほかのメンバーも準備OKにし、全員OKのルームが解禁される
    @Test
    func othersFollowReadyAndRoomUnlocks() async throws {
        let server = InMemoryServer.demo(.roomWithCandidates)
        let autoMembers = InMemoryAutoMembers(server: server)
        let roomID = DemoScenario.roomID
        #expect(server.rooms[roomID]?.room.readyCount == 0)

        try await server.setReady(true, roomID: roomID, userID: DemoScenario.myUserID)
        #expect(await AsyncTestSupport.eventually { server.rooms[roomID]?.room.status == .unlocked })
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.readyCount == room.memberCount)
        withExtendedLifetime(autoMembers) {}
    }

    /// 自分が準備OKにしていなければ、ほかのメンバーは準備OKにしない
    @Test
    func othersStayUnreadyUntilIAmReady() async throws {
        let server = InMemoryServer.demo(.roomWithCandidates)
        let autoMembers = InMemoryAutoMembers(server: server)
        await InMemoryAutoMembers.respond(on: server)
        #expect(server.rooms[DemoScenario.roomID]?.room.readyCount == 0)
        withExtendedLifetime(autoMembers) {}
    }

    /// 自分が引き直しを提案すると、ほかのメンバーが賛成して可決し、前回の当選が除外される（F-43）
    @Test
    func othersApproveRerollAndItPasses() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        let autoMembers = InMemoryAutoMembers(server: server)
        let roomID = DemoScenario.unlockedRoomID
        let drawn = try await server.drawGacha(RoomRequest(roomId: roomID))

        try await server.proposeReroll(RoomRequest(roomId: roomID))
        #expect(await AsyncTestSupport.eventually { server.rooms[roomID]?.room.reroll.status == .passed })
        let room = try #require(server.rooms[roomID]?.room)
        #expect(room.status == .unlocked)
        #expect(room.excludedCandidateIds == [drawn.candidateId])
        withExtendedLifetime(autoMembers) {}
    }

    /// 持ち主が手放すと購読をやめる（Task を止め、擬似のサーバーの購読が外れる）
    @Test
    func stopsObservingWhenReleased() async {
        let server = InMemoryServer.demo(.empty)
        let before = server.subscriberCount
        var autoMembers: InMemoryAutoMembers? = InMemoryAutoMembers(server: server)
        #expect(server.subscriberCount == before + 1)
        withExtendedLifetime(autoMembers) {}
        autoMembers = nil
        #expect(await AsyncTestSupport.eventually { server.subscriberCount == before })
    }

    /// `-ui-auto-members` は `-uiTesting` のときだけ効く（本番・撮影モードでは、ほかのメンバーの操作を返さない）
    @Test
    func launchArgumentWorksOnlyWhenUITesting() {
        let argument = LaunchContext.autoMembersArgument
        #expect(LaunchContext(arguments: ["Dokogacha", "-uiTesting", argument], environment: [:]).autoMembers)
        #expect(!LaunchContext(arguments: ["Dokogacha", "-uiTesting"], environment: [:]).autoMembers)
        #expect(!LaunchContext(arguments: ["Dokogacha", argument], environment: [:]).autoMembers)
        #expect(!LaunchContext(arguments: ["Dokogacha", "-screenshot-demo", argument], environment: [:]).autoMembers)
    }
}
