//
//  GachaModelReplayTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-13 のほかの人が回したときの自動再生（F-41）・見終えた抽選・「視差効果を減らす」の即時表示を、`GachaModel` と擬似のサーバーで確かめる
struct GachaModelReplayTests {
    typealias Fixture = GachaModelTests.Fixture

    static let roomID = GachaModelTests.roomID
    static let haruka = GachaModelTests.haruka

    // MARK: - ほかの人が回した

    /// 待機中にほかの人が回したら、「はるかさんが回しました！」を出して同じ演出（揺れ → 落下）を自動で再生する。
    /// レバーの触覚は鳴らさず、見終えた抽選として覚える
    @Test
    func othersDrawReplaysAutomatically() async throws {
        let fixture = GachaModelTests.makeFixture()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        let response = try await fixture.server.device(of: Self.haruka).drawGacha(RoomRequest(roomId: Self.roomID))
        #expect(await AsyncTestSupport.eventually { model.phase == .spinning && fixture.clock.isWaiting })
        #expect(model.drawnByName == "はるか")
        #expect(model.caption == .drawnByOther(name: "はるか"))
        #expect(model.drawID == response.drawId)
        #expect(!model.canTurnLever)
        #expect(!model.canClose)

        fixture.clock.holds = false
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(model.winnerCandidateID == response.candidateId)
        #expect(fixture.seenDraws.hasSeen(drawID: response.drawId))
        let ticks = Array(repeating: GachaCue.spinTick, count: GachaTimeline.tickCount)
        #expect(fixture.cues.cues == ticks + [.capsuleLanded])
        #expect(fixture.functions.drawRequests.isEmpty)
    }

    /// 画面を開いたときにまだ見ていない抽選で `drawn` なら、同じく再生する（S-07 から自動で開いたとき）
    @Test
    func unseenDrawnRoomReplaysOnOpen() async throws {
        let fixture = GachaModelTests.makeFixture(holdsClock: false)
        let response = try await fixture.server.device(of: Self.haruka).drawGacha(RoomRequest(roomId: Self.roomID))
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(model.drawnByName == "はるか")
        #expect(model.drawID == response.drawId)
        #expect(fixture.cues.cues.contains(.capsuleLanded))
    }

    /// 見終えた抽選は再生せず、初めから取り出し口にカプセルがある（同じ抽選を 2 回再生しない）
    @Test
    func seenDrawIsNotReplayed() async throws {
        let setup = GachaModelTests.makeFixture()
        let response = try await setup.server.device(of: Self.haruka).drawGacha(RoomRequest(roomId: Self.roomID))
        let fixture = Self.fixture(sharing: setup.server, seen: [response.drawId])
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(model.drawID == response.drawId)
        #expect(model.winnerCandidateID == response.candidateId)
        #expect(model.isCapsuleEnabled)
        #expect(fixture.clock.requested.isEmpty)
        #expect(fixture.cues.cues.isEmpty)

        // 開けると、開け終える
        fixture.clock.holds = false
        await model.openCapsule()
        #expect(model.phase == .opened)
        #expect(fixture.cues.cues == [.capsuleOpened])
    }

    // MARK: - 視差効果を減らす

    /// 「視差効果を減らす」では待たずに取り出しまで進み（回転中の刻みは鳴らさない）、開けるのもすぐに終わる
    @Test
    func reduceMotionShowsCapsuleImmediately() async throws {
        let fixture = GachaModelTests.makeFixture()
        let model = fixture.model
        model.reducesMotion = true
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        await model.turnLever()
        #expect(model.phase == .dispensed)
        #expect(model.isCapsuleEnabled)
        await model.openCapsule()
        #expect(model.phase == .opened)
        #expect(fixture.clock.requested.isEmpty)
        #expect(fixture.cues.cues == [.leverPulled, .capsuleLanded, .capsuleOpened])
    }

    /// 「視差効果を減らす」では、ほかの人が回したときもすぐに取り出しにする
    @Test
    func reduceMotionReplayIsImmediate() async throws {
        let fixture = GachaModelTests.makeFixture()
        let model = fixture.model
        model.reducesMotion = true
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        _ = try await fixture.server.device(of: Self.haruka).drawGacha(RoomRequest(roomId: Self.roomID))
        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(fixture.clock.requested.isEmpty)
        #expect(model.drawnByName == "はるか")
    }

    // MARK: - 道具

    /// 同じ擬似のサーバーを使う、別の画面の道具（見終えた抽選を決めて作る）
    static func fixture(sharing server: InMemoryServer, seen: Set<String>) -> Fixture {
        let functions = DrawControlledFunctions(server: server)
        let clock = GachaStepClock()
        let seenDraws = InMemorySeenDrawStore(seenIDs: seen)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = GachaModel(
            roomID: roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: functions,
            toasts: toasts,
            seenDraws: seenDraws,
            sleep: clock.sleep,
            resubscribeDelay: RoomModelTests.immediateResubscribe
        )
        let recorder = GachaModelTests.CueRecorder()
        model.cueHandler = { recorder.cues.append($0) }
        return Fixture(
            server: server, functions: functions, clock: clock, seenDraws: seenDraws, toasts: toasts, model: model, cues: recorder
        )
    }
}
