//
//  AnalyticsGachaEventTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ガチャ・結果（行き先きっぷ）・引き直し・終了の操作から、05 の §9 のイベントを名前とパラメータどおりに送ることを、
/// 画面の Model と擬似のサーバーで確かめる
struct AnalyticsGachaEventTests {
    // MARK: gacha_draw

    static func gachaModel(_ server: InMemoryServer, analytics: RecordingAnalyticsService) -> GachaModel {
        let model = GachaModel(
            roomID: GachaModelTests.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            seenDraws: InMemorySeenDrawStore(),
            sleep: { _ in },
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
        model.reducesMotion = true
        return model
    }

    /// 自分が回したら、抽選の対象の数・引き直しか・レア当選かを送る。レア当選かはサーバーの抽選の記録と同じになる
    @Test
    func gachaDrawSendsCountRerollAndRarity() async throws {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let analytics = RecordingAnalyticsService()
        let model = Self.gachaModel(server, analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        await model.turnLever()

        let drawID = try #require(model.drawID)
        let draw = try #require(server.rooms[GachaModelTests.roomID]?.draws[drawID])
        #expect(analytics.events == [.gachaDraw(candidateCount: 3, isReroll: false, rare: WinRarity.isRare(draw))])
        #expect(analytics.events.first?.name == "gacha_draw")
        #expect(analytics.events.first?.parameters["candidate_count"] == .int(3))
        #expect(analytics.events.first?.parameters["is_reroll"] == .int(0))
    }

    /// 先にほかの人が回していた（同時に回して先を越された）ときは、自分では抽選していないので送らない
    @Test
    func alreadyDrawnSendsNothing() async throws {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let analytics = RecordingAnalyticsService()
        let functions = DrawControlledFunctions(server: server)
        functions.drawBehavior = .suspend
        let model = GachaModel(
            roomID: GachaModelTests.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: functions,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            seenDraws: InMemorySeenDrawStore(),
            sleep: { _ in },
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
        model.reducesMotion = true
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        let turning = Task { await model.turnLever() }
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        _ = try await server.device(of: GachaModelTests.haruka).drawGacha(RoomRequest(roomId: GachaModelTests.roomID))
        functions.finish()
        await turning.value

        #expect(model.drawID != nil)
        #expect(analytics.events.isEmpty)
    }

    // MARK: ticket_share・reroll_propose・reroll_result・room_close

    static func resultModel(_ server: InMemoryServer, drawID: String, analytics: RecordingAnalyticsService) -> ResultModel {
        ResultModel(
            roomID: ResultModelTests.roomID,
            drawID: drawID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            mapOpener: RecordingMapOpener(),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
    }

    /// 「きっぷを共有」でパラメータの無い ticket_share を送る
    @Test
    func shareSendsTicketShare() async throws {
        let (server, drawID) = try await ResultModelTests.drawnServer()
        let analytics = RecordingAnalyticsService()
        let model = Self.resultModel(server, drawID: drawID, analytics: analytics)

        model.shareTapped()

        #expect(analytics.events == [.ticketShare])
        #expect(analytics.events.first?.parameters.isEmpty == true)
    }

    /// 引き直しを提案できたら reroll_propose を送る。提案できない状態（提案済み）では送らない
    @Test
    func proposeSendsRerollPropose() async throws {
        let (server, drawID) = try await ResultModelTests.drawnServer()
        let analytics = RecordingAnalyticsService()
        let model = Self.resultModel(server, drawID: drawID, analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.rerollPanel == .proposable })

        await model.proposeReroll()
        #expect(analytics.events == [.rerollPropose])
        #expect(await AsyncTestSupport.eventually { model.rerollPanel != .proposable })
        await model.proposeReroll()
        #expect(analytics.events == [.rerollPropose])
    }

    /// S-07 を出している間に引き直しの投票が可決したら、reroll_result の passed を 1 で送る
    @Test
    func rerollPassedSendsResult() async throws {
        let (server, _) = try await ResultModelTests.drawnServer()
        let analytics = RecordingAnalyticsService()
        let room = RoomModel(
            roomID: ResultModelTests.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics,
            logsRoomChanges: true
        )
        try await server.device(of: ResultModelTests.haruka).proposeReroll(RoomRequest(roomId: ResultModelTests.roomID))
        let observing = Task { await room.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { room.room?.reroll.status == .voting })

        try await server.voteReroll(VoteRerollRequest(roomId: ResultModelTests.roomID, approve: true))

        #expect(await AsyncTestSupport.eventually { room.room?.reroll.status == .passed })
        #expect(analytics.events == [.rerollResult(passed: true)])
        #expect(analytics.events.first?.parameters == ["passed": .int(1)])
    }

    /// 作成者が「この行き先で決定」で終了できたら、auto を 0 で送る
    @Test
    func closeSendsRoomCloseNotAuto() async {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let analytics = RecordingAnalyticsService()
        let model = ResultCloseModel(
            roomID: ResultCloseModelTests.roomID,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            analytics: analytics
        )

        #expect(await model.close())
        #expect(analytics.events == [.roomClose(auto: false, early: false)])
        #expect(analytics.events.first?.parameters == ["auto": .int(0), "early": .int(0)])
    }

    /// 終了に失敗したら送らない
    @Test
    func closeFailureSendsNothing() async {
        let analytics = RecordingAnalyticsService()
        let model = ResultCloseModel(
            roomID: ResultCloseModelTests.roomID,
            functions: UnavailableServer(),
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            analytics: analytics
        )
        #expect(await !model.close())
        #expect(analytics.events.isEmpty)
    }

    /// S-14 の Model は、中の「この行き先で決定」にも同じ窓口を渡す
    @Test
    func resultPassesAnalyticsToClosing() async {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let analytics = RecordingAnalyticsService()
        let model = ResultModel(
            roomID: ResultCloseModelTests.roomID,
            drawID: "unused",
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            mapOpener: RecordingMapOpener(),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
        #expect(await model.closing.close())
        #expect(analytics.events == [.roomClose(auto: false, early: false)])
    }
}
