//
//  HomeModelMemoriesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ホーム（`HomeModel`）の思い出のきっぷ（03 の S-02 の 3・F-44）を擬似のサーバーで確かめる
struct HomeModelMemoriesTests {
    /// 終了したルームが無ければ、一覧が届いた後に空の表示にする（届くまでは読み込み中）
    @Test
    func emptyWhenNoClosedRooms() async {
        let model = HomeModelTests.makeModel(InMemoryServer.demo(.severalRooms))
        #expect(model.isMemoriesLoading)
        #expect(!model.isMemoriesEmpty)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.isMemoriesEmpty })
        #expect(!model.isMemoriesLoading)
        #expect(model.memoryTickets.isEmpty)
    }

    /// 終了したルームを新しい順に 5 枚まで出し、「すべて見る」で 6 枚目も出す。当選した場所と外れた候補の数を出す
    @Test
    func listsClosedRoomsNewestFirst() async throws {
        let model = HomeModelTests.makeModel(InMemoryServer.demo(.memories) { RoomModelTests.now })
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.memoryTickets.count == 6 })
        #expect(model.visibleMemoryTickets.map(\.roomName) == ["夏の日帰り", "サークルの合宿", "ゼミの打ち上げ", "家族でおでかけ", "秋の紅葉狩り"])
        let first = try #require(model.visibleMemoryTickets.first)
        #expect(first.destinationName == "城ヶ島")
        #expect(first.leftoverCount == 4)
        #expect(model.visibleMemoryTickets[1].leftoverCount == 0)
        #expect(model.hasMoreMemories)

        model.showAllMemoriesTapped()
        #expect(model.visibleMemoryTickets.count == 6)
        #expect(!model.hasMoreMemories)
        // 進行中のルームには終了したルームを出さない
        #expect(model.cards.map(\.id).sorted() == [DemoScenario.drawnRoomID, DemoScenario.othersDrawnRoomID])
    }

    /// 作成者がルームを終了すると、進行中のルームから消えて、思い出のきっぷの先頭に出る（購読で反映）
    @Test
    func closingMovesRoomToMemories() async throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let model = HomeModelTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.cards.count == 2 && model.isMemoriesEmpty })

        try await server.closeRoom(RoomRequest(roomId: DemoScenario.drawnRoomID))
        #expect(await AsyncTestSupport.eventually { model.memoryTickets.count == 1 })
        let ticket = try #require(model.memoryTickets.first)
        #expect(ticket.id == DemoScenario.drawnRoomID)
        #expect(ticket.roomName == "週末のランチ")
        #expect(ticket.destinationName == "サンシャイン水族館")
        #expect(ticket.leftoverCount == 2)
        #expect(ticket.date == RoomModelTests.now)
        #expect(ticket.drawID == server.rooms[DemoScenario.drawnRoomID]?.room.currentDrawId)
        #expect(model.cards.map(\.id) == [DemoScenario.othersDrawnRoomID])
    }
}
