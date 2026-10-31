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
        room.winnerCandidateId = drawID == nil ? nil : "demo-candidate-1"
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
        #expect(model.gachaButtonState == .result(drawID: response.drawId))
        // 画面を出している間に drawn になったときは、S-14 を自動では出さない（S-13 の演出の後に進む）
        #expect(model.resultToOpen == nil)
    }

    /// 開いたときに drawn・closed のルームなら、S-14 を自動で出す（03 の §2・02 の §6.2）。出していた間に変わったとき・抽選の ID が無いときは出さない
    @Test
    func resultOpensForAlreadyDrawnRoom() throws {
        let room = try Self.drawnRoom()
        #expect(DrawReplay.resultDrawID(previous: nil, room: room) == "d1")
        var closed = room
        closed.status = .closed
        #expect(DrawReplay.resultDrawID(previous: nil, room: closed) == "d1")
        #expect(DrawReplay.resultDrawID(previous: .unlocked, room: room) == nil)
        #expect(DrawReplay.resultDrawID(previous: .drawn, room: room) == nil)
        #expect(DrawReplay.resultDrawID(previous: nil, room: try Self.drawnRoom(drawID: nil)) == nil)
        #expect(DrawReplay.resultDrawID(previous: nil, room: try Self.drawnRoom(drawID: "")) == nil)
        var unlocked = room
        unlocked.status = .unlocked
        #expect(DrawReplay.resultDrawID(previous: nil, room: unlocked) == nil)
    }

    /// 引き直しが可決して unlocked に戻ったまま途中で終了したルームは、前の当選の抽選の ID が残っていても S-14 を出さない（Discussion #155）
    @Test
    func resultDoesNotOpenForRoomEndedWithoutResult() throws {
        var rerolled = try Self.drawnRoom()
        rerolled.status = .closed
        rerolled.excludedCandidateIds = ["demo-candidate-1"]
        #expect(DrawReplay.resultDrawID(previous: nil, room: rerolled) == nil)
        var early = try Self.drawnRoom(drawID: nil)
        early.status = .closed
        #expect(DrawReplay.resultDrawID(previous: nil, room: early) == nil)
    }

    /// アプリを閉じていた人がすでに drawn のルームを開くと、S-14 を出す抽選が入る（F-40〜44 の AC「後から開くと、結果画面が表示される」）
    @Test
    func roomModelOpensResultForAlreadyDrawnRoom() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        let response = try await server.device(of: "demo-haruka").drawGacha(RoomRequest(roomId: DemoScenario.unlockedRoomID))
        let model = RoomModel(
            roomID: DemoScenario.unlockedRoomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            seenDraws: InMemorySeenDrawStore()
        )
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.resultToOpen == response.drawId })
        #expect(model.drawToReplay == nil)
        model.resultOpened()
        #expect(model.resultToOpen == nil)
        #expect(model.gachaButtonState == .result(drawID: response.drawId))
    }
}
