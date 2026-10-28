//
//  DataServicesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 起動のしかたから、データ層の実装（Firebase・擬似のサーバー・接続できない）とデモのデータを選ぶことを確かめる
struct DataServicesTests {
    @Test
    func uiTestingUsesInMemoryServerWithScenario() throws {
        let launch = LaunchContext(arguments: ["Dokogacha", "-uiTesting", "-demo-scenario", "room-with-candidates"], environment: [:])
        #expect(launch.demoScenario == .roomWithCandidates)
        let services = DataServices.make(connection: .disabled(.uiTesting), launch: launch)
        #expect(services.backend == .inMemory(.roomWithCandidates))
        let server = try #require(services.inMemoryServer)
        #expect(server.signedInUserID == DemoScenario.myUserID)
        #expect(server.rooms[DemoScenario.roomID]?.candidates.count == 3)
    }

    /// Unit テストのホストは、起動引数にかかわらず空の擬似のサーバー
    @Test
    func unitTestHostUsesEmptyInMemoryServer() {
        let launch = LaunchContext(arguments: ["Dokogacha", "-demo-scenario", "one-room"], environment: [:])
        #expect(DataServices.make(connection: .disabled(.unitTestHost), launch: launch).backend == .inMemory(.empty))
    }

    @Test(arguments: [ServerConnection.unavailable(.missingOptionsFile(nil)), .notStarted])
    func unavailableConnectionUsesUnavailableServer(connection: ServerConnection) async {
        let services = DataServices.make(connection: connection, launch: LaunchContext(arguments: [], environment: [:]))
        #expect(services.backend == .unavailable)
        #expect(!services.allowsSignIn)
        await #expect(throws: AppError(.serverUnavailable)) {
            try await services.functions.joinRoom(JoinRoomRequest(inviteCode: "DK729Q"))
        }
        var iterator = services.rooms.room(id: "r1").makeAsyncIterator()
        #expect(await iterator.next() == .failure(AppError(.serverUnavailable)))
        #expect(await iterator.next() == nil)
    }

    @Test(arguments: [
        ([String](), DemoScenario.empty),
        (["-demo-scenario"], .empty),
        (["-demo-scenario", "unknown"], .empty),
        (["-demo-scenario", "first-launch"], .firstLaunch),
        (["-uiTesting", "-demo-scenario", "one-room"], .oneRoom)
    ])
    func parsesDemoScenario(arguments: [String], expected: DemoScenario) {
        #expect(DemoScenario.from(arguments: arguments) == expected)
    }

    /// 撮影モードでシナリオを指定しなければ、ルームが並んだ `several-rooms` で撮る（指定すればそれに従う）
    @Test
    func screenshotDemoFallsBackToSeveralRooms() {
        let screenshot = LaunchContext(arguments: ["-screenshot-demo", "-screenshot-scene", "home"], environment: [:])
        #expect(screenshot.demoScenario == .severalRooms)
        let chosen = LaunchContext(arguments: ["-screenshot-demo", "-demo-scenario", "empty"], environment: [:])
        #expect(chosen.demoScenario == .empty)
        let uiTesting = LaunchContext(arguments: ["-uiTesting"], environment: [:])
        #expect(uiTesting.demoScenario == .empty)
    }

    /// `several-rooms`: 自分が入っている進行中のルームが 3 つ（状態が 2 種類・ほかの人が作ったものを含む）
    @Test
    func severalRoomsScenarioHasThreeActiveRooms() {
        let server = InMemoryServer.demo(.severalRooms)
        let rooms = server.rooms.values.map(\.room)
        #expect(rooms.count == 3)
        #expect(rooms.allSatisfy { $0.memberIds.contains(DemoScenario.myUserID) })
        #expect(Set(rooms.map(\.status)) == [.open, .unlocked])
        #expect(rooms.contains { $0.ownerId != DemoScenario.myUserID })
        for record in server.rooms.values {
            // 数のフィールドは、メンバーと候補の中身とそろえる（Functions が更新するものと同じ）
            #expect(record.room.memberCount == record.members.count)
            #expect(record.room.readyCount == record.members.values.filter(\.ready).count)
            #expect(record.room.candidateCount == record.candidates.count)
            #expect(server.inviteCodes[record.room.inviteCode] != nil)
        }
    }

    @Test
    func scenariosHaveExpectedData() {
        let firstLaunch = InMemoryServer.demo(.firstLaunch)
        #expect(firstLaunch.users.isEmpty)
        #expect(firstLaunch.rooms.isEmpty)

        let oneRoom = InMemoryServer.demo(.oneRoom)
        let record = oneRoom.rooms[DemoScenario.roomID]
        #expect(record?.room.ownerId == DemoScenario.myUserID)
        #expect(record?.room.memberCount == 4)
        #expect(record?.members.count == 4)
        #expect(record?.candidates.isEmpty == true)
        #expect(oneRoom.inviteCodes[DemoScenario.inviteCode]?.roomId == DemoScenario.roomID)
        #expect(InviteCode(DemoScenario.inviteCode) != nil)
    }
}
