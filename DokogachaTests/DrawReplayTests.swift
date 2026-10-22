//
//  DrawReplayTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ほかの人がガチャを回したときに、S-07 から S-13 を開いて演出を再生するか（F-41）
struct DrawReplayTests {
    /// `drawn` のルーム（抽選の ID は d1）
    static func drawnRoom(drawID: String? = "d1") throws -> Room {
        var room = try #require(InMemoryServer.demo(.roomWithCandidates).rooms[DemoScenario.roomID]?.room)
        room.status = .drawn
        room.currentDrawId = drawID
        return room
    }

    /// 出していたルームが drawn になり、まだ見ていない抽選なら再生する
    @Test
    func replaysNewDraw() throws {
        let room = try Self.drawnRoom()
        #expect(DrawReplay.drawID(previous: .unlocked, room: room) { _ in false } == "d1")
        #expect(DrawReplay.drawID(previous: .open, room: room) { _ in false } == "d1")
    }

    /// 見終えた抽選・開いたときにすでに drawn・前から drawn・抽選の ID が無いときは再生しない
    @Test
    func skipsSeenOrAlreadyDrawn() throws {
        let room = try Self.drawnRoom()
        #expect(DrawReplay.drawID(previous: .unlocked, room: room) { $0 == "d1" } == nil)
        #expect(DrawReplay.drawID(previous: nil, room: room) { _ in false } == nil)
        #expect(DrawReplay.drawID(previous: .drawn, room: room) { _ in false } == nil)
        #expect(DrawReplay.drawID(previous: .unlocked, room: try Self.drawnRoom(drawID: nil)) { _ in false } == nil)
        #expect(DrawReplay.drawID(previous: .unlocked, room: try Self.drawnRoom(drawID: "")) { _ in false } == nil)
        var unlocked = room
        unlocked.status = .unlocked
        #expect(DrawReplay.drawID(previous: .open, room: unlocked) { _ in false } == nil)
    }

    /// S-07 を出している間にほかの人が回したら、`drawToReplay` に抽選の ID が入り、開いたら消える。
    /// 見終えた抽選（自分が回した後に戻ったときなど）では入らない
    @Test
    func roomModelRequestsReplay() async throws {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let seen = InMemorySeenDrawStore()
        let model = RoomModel(
            roomID: DemoScenario.unlockedRoomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            seenDraws: seen
        )
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })

        let response = try await server.device(of: "demo-haruka").drawGacha(RoomRequest(roomId: DemoScenario.unlockedRoomID))
        #expect(await AsyncTestSupport.eventually { model.drawToReplay == response.drawId })
        model.replayOpened()
        #expect(model.drawToReplay == nil)
        #expect(model.gachaButtonState == nil)
    }
}
