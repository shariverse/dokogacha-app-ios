//
//  InMemoryOwnerEndsRoomTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// UI テスト用の、ほかの人が作ったルームを作成者が途中で終了したことにする仕組み（`InMemoryOwnerEndsRoom`・`-ui-owner-ends-room`）と、
/// 途中で終了したルームのデモのシナリオ（`ended-room`）
struct InMemoryOwnerEndsRoomTests {
    /// ほかの人が作ったルームで自分が準備OKにしたら、作成者（はるか）が途中で終了する。自分が作ったルームは終了しない
    @Test
    func ownerEndsOthersRoomAfterIReady() async throws {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let observer = InMemoryOwnerEndsRoom(server: server)
        defer { withExtendedLifetime(observer) {} }

        try await server.setReady(true, roomID: DemoScenario.roomID, userID: DemoScenario.myUserID)
        try await server.setReady(true, roomID: DemoScenario.othersRoomID, userID: DemoScenario.myUserID)
        #expect(await AsyncTestSupport.eventually { server.rooms[DemoScenario.othersRoomID]?.room.status == .closed })
        #expect(server.rooms[DemoScenario.roomID]?.room.status != .closed)
        #expect(server.pastIdeas.isEmpty)
    }

    /// `-ui-owner-ends-room` は `-uiTesting` のときだけ効く
    @Test
    func launchArgumentWorksOnlyWhenUITesting() {
        let argument = LaunchContext.ownerEndsRoomArgument
        #expect(LaunchContext(arguments: ["Dokogacha", "-uiTesting", argument], environment: [:]).ownerEndsRoom)
        #expect(!LaunchContext(arguments: ["Dokogacha", "-uiTesting"], environment: [:]).ownerEndsRoom)
        #expect(!LaunchContext(arguments: ["Dokogacha", argument], environment: [:]).ownerEndsRoom)
        #expect(!LaunchContext(arguments: ["Dokogacha", "-screenshot-demo", argument], environment: [:]).ownerEndsRoom)
    }

    /// `ended-room` は、はるかが作った春のお花見が、抽選の前に途中で終了している（抽選の ID・当選が無い）。ほかは `several-rooms` と同じ
    @Test
    func endedRoomScenarioHasRoomEndedWithoutResult() throws {
        let server = InMemoryServer.demo(.endedRoom) { RoomModelTests.now }
        let room = try #require(server.rooms[DemoScenario.othersRoomID]?.room)
        #expect(room.status == .closed)
        #expect(room.closedAt != nil)
        #expect(room.currentDrawId == nil)
        #expect(RoomClosing.endedWithoutResult(room))
        #expect(room.memberIds.contains(DemoScenario.myUserID))
        #expect(server.rooms[DemoScenario.roomID]?.room.status == .open)
        #expect(server.rooms[DemoScenario.unlockedRoomID]?.room.status == .unlocked)
    }
}
