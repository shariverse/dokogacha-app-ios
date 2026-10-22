//
//  GachaModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 演出の時間を待つ処理の代わり。待つように頼まれた時間を覚え、`holds` なら `advance()` を呼ぶまで（または cancel まで）止まる（固定の時間で待たない）
final class GachaStepClock {
    /// 待つように頼まれた時間（頼まれた順）
    private(set) var requested: [Duration] = []
    /// true なら、`advance()` を呼ぶまで返さない。false ならすぐに返す
    var holds: Bool
    private var waiting: CheckedContinuation<Void, Never>?

    init(holds: Bool = true) {
        self.holds = holds
    }

    /// 止まっている待ちがあるか
    var isWaiting: Bool {
        waiting != nil
    }

    /// 頼まれた時間（秒）
    var requestedSeconds: [Double] {
        requested.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 }
    }

    /// `GachaModel` に渡す待つ処理
    var sleep: GachaModel.Sleep {
        { [self] duration in
            try await wait(duration)
        }
    }

    /// 止まっている待ちを 1 つ進める
    func advance() {
        let continuation = waiting
        waiting = nil
        continuation?.resume()
    }

    private func wait(_ duration: Duration) async throws {
        requested.append(duration)
        if holds {
            // cancel されたら止めていた待ちを進め、続く `checkCancellation` で投げる（continuation を残したままにしない）
            await withTaskCancellationHandler {
                await withCheckedContinuation { waiting = $0 }
            } onCancel: { [self] in
                Task { @MainActor in advance() }
            }
        }
        try Task.checkCancellation()
    }
}

/// S-13 の自分が回すとき（F-40・F-41）を、`GachaModel` と擬似のサーバーで確かめる。
///
/// デモのルームは `several-rooms` の解禁済みのルーム（週末のランチ。自分・はるか・そうたの全員が準備OK、候補 3 件）
struct GachaModelTests {
    static let roomID = DemoScenario.unlockedRoomID
    static let haruka = "demo-haruka"

    /// テストの道具一式
    struct Fixture {
        let server: InMemoryServer
        let functions: DrawControlledFunctions
        let clock: GachaStepClock
        let seenDraws: InMemorySeenDrawStore
        let toasts: DGToastCenter
        let model: GachaModel
        /// 出た合図（出た順）
        let cues: CueRecorder
    }

    /// 合図を覚える
    final class CueRecorder {
        var cues: [GachaCue] = []
    }

    static func makeFixture(holdsClock: Bool = true, seen: Set<String> = []) -> Fixture {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let functions = DrawControlledFunctions(server: server)
        let clock = GachaStepClock(holds: holdsClock)
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
        let recorder = CueRecorder()
        model.cueHandler = { recorder.cues.append($0) }
        return Fixture(
            server: server, functions: functions, clock: clock, seenDraws: seenDraws, toasts: toasts, model: model, cues: recorder
        )
    }

    /// ルームと候補が届くまで待つ
    static func waitUntilLoaded(_ model: GachaModel) async -> Bool {
        await AsyncTestSupport.eventually { model.room != nil && model.candidates.count == 3 }
    }

    // MARK: - 段階の遷移

    /// レバーを押すと、回転中（0.2 秒ごとの刻み × 7・1.6 秒）→ 落下（底に当たって合図）→ 取り出し（押せる）→ 開く（0.5 秒）→ 開け終える、の順に進む。
    /// 演出の途中はレバー・カプセル・閉じるを押せない
    @Test
    func turnLeverRunsStagesInOrder() async throws {
        let fixture = Self.makeFixture()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(model.caption == .ready(isReroll: false))
        #expect(model.canTurnLever)
        #expect(model.capsuleCount == 3)

        model.leverTapped()
        #expect(await AsyncTestSupport.eventually { fixture.clock.isWaiting })
        #expect(model.phase == .spinning)
        #expect(model.caption == .spinning)
        #expect(fixture.cues.cues == [.leverPulled])
        #expect(!model.canTurnLever)
        #expect(!model.canClose)
        #expect(fixture.functions.drawRequests == [RoomRequest(roomId: Self.roomID)])

        for tick in 1...GachaTimeline.tickCount {
            fixture.clock.advance()
            #expect(await AsyncTestSupport.eventually { fixture.clock.isWaiting && fixture.cues.cues.count == tick + 1 })
            #expect(model.phase == .spinning)
        }
        // 最後の 0.2 秒で回転が終わり、結果は返っているので落とし始める
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { model.phase == .dropping && fixture.clock.isWaiting })
        #expect(model.caption == .dispensed)
        #expect(!model.isCapsuleEnabled)
        #expect(fixture.cues.cues.last == .spinTick)

        // 底に当たったら合図を出し、見終えた抽選として覚える。まだ押せない
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { fixture.cues.cues.last == .capsuleLanded && fixture.clock.isWaiting })
        let drawID = try #require(model.drawID)
        #expect(fixture.seenDraws.hasSeen(drawID: drawID))
        #expect(model.phase == .dropping)
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(model.isCapsuleEnabled)
        #expect(model.canClose)
        #expect(model.winnerCandidateID == fixture.server.rooms[Self.roomID]?.room.winnerCandidateId)
        #expect(model.drawnByName == nil)

        model.capsuleTapped()
        #expect(await AsyncTestSupport.eventually { model.phase == .opening && fixture.clock.isWaiting })
        #expect(!model.isCapsuleEnabled)
        #expect(!model.canClose)
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { model.phase == .opened })

        let ticks = Array(repeating: GachaCue.spinTick, count: GachaTimeline.tickCount)
        #expect(fixture.cues.cues == [.leverPulled] + ticks + [.capsuleLanded, .capsuleOpened])
        let expectedSeconds = Array(repeating: 0.2, count: GachaTimeline.tickCount + 1) + [0.385, 0.415, 0.5]
        #expect(fixture.clock.requestedSeconds.count == expectedSeconds.count)
        for (actual, expected) in zip(fixture.clock.requestedSeconds, expectedSeconds) {
            #expect(abs(actual - expected) < 1e-9)
        }
    }

    /// 回転が終わっても結果が返るまではカプセルを落とさない（02 の §6.2「結果が返り、かつ演出が終わったら」）。
    /// 送っている途中にもう一度押しても送らない（二重に回さない）
    @Test
    func waitsForDrawResultAndIgnoresDoubleTap() async throws {
        let fixture = Self.makeFixture(holdsClock: false)
        fixture.functions.drawBehavior = .suspend
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.leverTapped()
        #expect(await AsyncTestSupport.eventually {
            fixture.functions.isWaiting && fixture.clock.requested.count == GachaTimeline.tickCount + 1
        })
        model.leverTapped()
        await model.turnLever()
        #expect(fixture.functions.drawRequests.count == 1)
        #expect(model.phase == .spinning)
        #expect(model.isDrawing)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(!model.isDrawing)
        #expect(fixture.server.rooms[Self.roomID]?.draws.count == 1)
    }

    // MARK: - エラー

    /// 通信のエラーでは演出を止めて待機に戻し、「通信できませんでした。もう一度回してください」を出す。ルームは unlocked のまま、もう一度回せる
    @Test
    func networkErrorStopsAndAllowsRetry() async throws {
        let fixture = Self.makeFixture()
        fixture.functions.drawBehavior = .fail(AppError(.network, code: .unavailable))
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.turnLever()
        #expect(model.phase == .idle)
        #expect(fixture.toasts.current?.text == "通信できませんでした。もう一度回してください")
        #expect(fixture.server.rooms[Self.roomID]?.room.status == .unlocked)
        #expect(model.canTurnLever)
        #expect(model.drawID == nil)
        #expect(fixture.cues.cues == [.leverPulled])

        fixture.functions.drawBehavior = .pass
        fixture.clock.holds = false
        await model.turnLever()
        #expect(model.phase == .dispensed)
    }

    /// 回せない理由が分かるもの（解禁していない・候補が無い）は、`AppError` の文言を出す
    @Test(arguments: [AppError.Reason.roomNotUnlocked, .noCandidates])
    func reasonErrorShowsReasonMessage(_ reason: AppError.Reason) async throws {
        let fixture = Self.makeFixture()
        fixture.functions.drawBehavior = .fail(InMemoryServer.error(reason))
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.turnLever()
        #expect(model.phase == .idle)
        #expect(fixture.toasts.current?.text == reason.message)
    }

    /// cancel（画面を閉じた）ではトーストを出さない
    @Test
    func cancellationShowsNoToast() async throws {
        #expect(GachaModel.failureMessage(for: AppError(.internal)) == "通信できませんでした。もう一度回してください")
        #expect(GachaModel.failureMessage(for: AppError(.offline)) == "オフラインのため操作できません")
        let fixture = Self.makeFixture()
        fixture.functions.drawBehavior = .fail(CancellationError())
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        await model.turnLever()
        #expect(model.phase == .idle)
        #expect(fixture.toasts.current == nil)
    }

    // MARK: - 同時に回した

    /// 送っている間にほかの人が先に回したら（`alreadyDrawn`）、先に回した人の名前を出して同じ結果を見せる（02 の F-40 の AC）
    @Test
    func alreadyDrawnShowsFirstDrawer() async throws {
        let fixture = Self.makeFixture(holdsClock: false)
        fixture.functions.drawBehavior = .suspend
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.leverTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        let first = try await fixture.server.device(of: Self.haruka).drawGacha(RoomRequest(roomId: Self.roomID))
        // 自分が回している途中に届いた drawn では、ほかの人の演出を始めない
        #expect(await AsyncTestSupport.eventually { model.room?.status == .drawn })
        #expect(model.drawID == nil)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.phase == .dispensed })
        #expect(model.drawID == first.drawId)
        #expect(model.winnerCandidateID == first.candidateId)
        #expect(model.drawnByName == "はるか")
        #expect(fixture.server.rooms[Self.roomID]?.draws.count == 1)
    }

    // MARK: - 止める

    /// 画面が消えたら（`stop()`）演出を止め、それ以上進めない
    @Test
    func stopCancelsAnimation() async throws {
        let fixture = Self.makeFixture()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.leverTapped()
        #expect(await AsyncTestSupport.eventually { fixture.clock.isWaiting })
        model.stop()
        fixture.clock.advance()
        #expect(await AsyncTestSupport.eventually { !model.isDrawing })
        #expect(model.phase == .spinning)
        #expect(fixture.cues.cues == [.leverPulled])
    }
}
