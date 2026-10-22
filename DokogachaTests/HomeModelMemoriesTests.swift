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

    /// 終了したルームを新しい順に 5 枚まで出し、「すべて見る」で 6 枚目も出す。当選した場所と外れた候補の数を出す。
    /// 押す前は終了したルームを 6 件だけ読み、当選した候補は出す 5 枚の分だけ購読する（PR #78 のレビュー）
    @Test
    func listsClosedRoomsNewestFirst() async throws {
        let repository = MemoriesRecordingRepository(server: InMemoryServer.demo(.memories) { RoomModelTests.now })
        let model = HomeModelTests.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.memoryTickets.count == 5 })
        #expect(model.visibleMemoryTickets.map(\.roomName) == ["夏の日帰り", "サークルの合宿", "ゼミの打ち上げ", "家族でおでかけ", "秋の紅葉狩り"])
        let first = try #require(model.visibleMemoryTickets.first)
        #expect(first.destinationName == "城ヶ島")
        #expect(first.leftoverCount == 4)
        #expect(model.visibleMemoryTickets[1].leftoverCount == 0)
        #expect(model.hasMoreMemories)
        #expect(repository.closedRoomLimits == [MemoryTicket.queryLimit])
        #expect(model.closedRooms.count == 6)
        #expect(Set(repository.candidateRoomIDs).count == 5)
        #expect(!repository.candidateRoomIDs.contains("\(DemoScenario.closedRoomIDPrefix)6"))

        model.showAllMemoriesTapped()
        #expect(await AsyncTestSupport.eventually { model.visibleMemoryTickets.count == 6 })
        #expect(!model.hasMoreMemories)
        #expect(repository.closedRoomLimits == [MemoryTicket.queryLimit, nil])
        #expect(repository.candidateRoomIDs.contains("\(DemoScenario.closedRoomIDPrefix)6"))
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

/// 終了したルームの購読の上限と、当選した候補を購読したルームを記録する窓口（それ以外は擬似のサーバーのまま）
final class MemoriesRecordingRepository: RoomRepository {
    let server: InMemoryServer
    /// `closedRooms` に渡された上限（呼ばれた順）
    private(set) var closedRoomLimits: [Int?] = []
    /// `candidate` を購読したルームの ID（呼ばれた順）
    private(set) var candidateRoomIDs: [String] = []

    init(server: InMemoryServer) {
        self.server = server
    }

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        server.activeRooms(userID: userID)
    }

    func closedRooms(userID: String, limit: Int?) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        closedRoomLimits.append(limit)
        return server.closedRooms(userID: userID, limit: limit)
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        server.room(id: roomID)
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        server.members(roomID: roomID)
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        server.candidates(roomID: roomID)
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        server.draw(roomID: roomID, drawID: drawID)
    }

    func candidate(roomID: String, candidateID: String) -> AsyncStream<LiveUpdate<Identified<Candidate>?>> {
        candidateRoomIDs.append(roomID)
        return server.candidate(roomID: roomID, candidateID: candidateID)
    }

    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        server.pastIdeas(userID: userID)
    }

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {}

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {}

    func markSeen(roomID: String, userID: String) async throws {}
}
