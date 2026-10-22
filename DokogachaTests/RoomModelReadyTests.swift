//
//  RoomModelReadyTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-07 の準備OK（F-30）・解禁の表示（F-31）・強制解禁（F-32）を、`RoomModel` と擬似のサーバーで確かめる。
///
/// デモのルーム（`room-with-candidates`）は、自分（たくみ・作成者）・はるか・そうた・みおの 4 人で、条件は「全員OK」、誰も準備OKでない
struct RoomModelReadyTests {
    static let haruka = "demo-haruka"
    static let sota = "demo-sota"
    static let mio = "demo-mio"

    static func makeServer() -> InMemoryServer {
        RoomModelTests.makeServer()
    }

    static func makeModel(
        _ repository: any RoomRepository,
        functions: any FunctionsClient = UnavailableServer(),
        toasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600)),
        userID: String = DemoScenario.myUserID
    ) -> RoomModel {
        RoomModelTests.makeModel(repository, functions: functions, toasts: toasts, userID: userID)
    }

    /// ほかのメンバーの端末から準備OKを変える
    static func setReady(_ ready: Bool, _ userID: String, on server: InMemoryServer) async {
        await server.device(of: userID).setReady(ready, roomID: DemoScenario.roomID)
    }

    // MARK: - 準備OK

    /// 押したらすぐに自分のバッジ・人数・ヒントが変わり、送り終えて自分の値が追いついたら確定する。送っている途中の二度押しは送らない
    @Test
    func readyIsOptimisticAndConfirmedBySubscription() async {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsReady = true
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))
        #expect(model.readyHint == .waitingForAll(remaining: 4))
        #expect(model.showsReadyButton)

        model.readyTapped()
        #expect(await AsyncTestSupport.eventually { repository.isHoldingReady })
        #expect(model.isReady)
        #expect(model.readyCount == 1)
        #expect(model.displayedMembers.first { $0.id == DemoScenario.myUserID }?.ready == true)
        #expect(model.readyHint == .waitingForAll(remaining: 3))

        // 二度押し
        await model.toggleReady()
        #expect(repository.readyCallCount == 1)

        repository.releaseReady()
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil })
        #expect(server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID]?.ready == true)
        #expect(model.isReady)
        #expect(model.readyCount == 1)

        // もう一度押すと取り消す
        repository.holdsReady = false
        await model.toggleReady()
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil && !model.isReady })
        #expect(server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID]?.ready == false)
        #expect(model.readyHint == .waitingForAll(remaining: 4))
    }

    /// 送っている途中にほかのメンバーの準備OKが届いても、自分の楽観的な準備OKを消さない
    @Test
    func readyStaysOptimisticWhileOthersChangesArrive() async {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsReady = true
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.readyTapped()
        #expect(await AsyncTestSupport.eventually { repository.isHoldingReady })
        await Self.setReady(true, Self.haruka, on: server)
        #expect(await AsyncTestSupport.eventually { model.members.first { $0.id == Self.haruka }?.ready == true })
        #expect(model.isReady)
        #expect(model.readyCount == 2)
        #expect(model.readyHint == .waitingForAll(remaining: 2))

        repository.releaseReady()
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil })
        #expect(model.isReady)
        #expect(model.readyCount == 2)
    }

    /// 送り終えた後に、書き込みの前の古いメンバーの値が届いても表示を戻さない。自分の値が追いついたら確定する
    @Test
    func staleMembersAfterSendingDoNotRevertReady() async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.feedMembers()
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        repository.sendMembers()
        #expect(await RoomModelTests.waitUntilLoaded(model))
        let before = try #require(server.rooms[DemoScenario.roomID]?.members)

        await model.toggleReady()
        #expect(model.pendingReady?.isSent == true)
        // 書き込みの前の値に、そうたの準備OKだけが入ったものが届く
        var stale = before
        stale[Self.sota]?.ready = true
        repository.sendMembers(stale)
        #expect(await AsyncTestSupport.eventually { model.members.first { $0.id == Self.sota }?.ready == true })
        #expect(model.isReady)
        #expect(model.readyCount == 2)

        repository.sendMembers()
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil })
        #expect(model.isReady)
    }

    /// 送る前に分かる失敗なら、表示を戻してトースト「通信できませんでした」を出す
    @Test
    func readyFailureRevertsAndShowsToast() async {
        let repository = RoomControlledRepository(server: Self.makeServer())
        repository.readyError = AppError(.serverUnavailable)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        await model.toggleReady()
        #expect(model.pendingReady == nil)
        #expect(!model.isReady)
        #expect(model.readyCount == 0)
        #expect(toasts.current?.text == "通信できませんでした")
    }

    /// ボタンはルームの `status` で出し分ける（`open`・`unlocked` で出し、`drawn`・`closed` では出さず送らない）
    @Test(arguments: [RoomStatus.drawn, .closed])
    func readyButtonFollowsStatus(_ status: RoomStatus) async {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        server.rooms[DemoScenario.roomID]?.room.status = .unlocked
        #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })
        #expect(model.showsReadyButton)
        #expect(!model.canForceUnlock)

        server.rooms[DemoScenario.roomID]?.room.status = status
        #expect(await AsyncTestSupport.eventually { model.room?.status == status })
        #expect(!model.showsReadyButton)
        #expect(!model.canForceUnlock)
        #expect(model.readyHint == nil)
        await model.toggleReady()
        #expect(repository.readyCallCount == 0)
    }

    /// 締切を過ぎても `checkDeadlines` が `unlocked` にするまでは、締切の文言のままでガチャも押せない。解禁したら解禁の文言
    @Test
    func deadlineHintWaitsForServerStatus() async {
        let server = Self.makeServer()
        let deadline = RoomModelTests.now.addingTimeInterval(-60)
        server.rooms[DemoScenario.roomID]?.room.settings.unlockRule = .deadline
        server.rooms[DemoScenario.roomID]?.room.settings.deadlineAt = deadline
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))
        #expect(model.readyHint == .waitingForDeadline(deadlineAt: deadline))
        #expect(model.gachaButtonState == .waiting)

        #expect(server.checkDeadlines() == 1)
        #expect(await AsyncTestSupport.eventually { model.readyHint == .unlocked })
        #expect(model.gachaButtonState == .ready)
    }

    // MARK: - 解禁の表示

    /// 全員OKで最後の 1 人（自分）が準備OKにすると、自分の画面もほかのメンバーの画面も「ガチャ解禁！」になる。
    /// 解禁の後に誰かが取り消すと、どちらの画面も `open` に戻る（F-30〜32 の AC）
    @Test
    func lastReadyUnlocksEveryScreen() async {
        let server = Self.makeServer()
        let mine = Self.makeModel(server)
        // はるかの画面（購読するだけ。はるかの書き込みははるかの端末から行う）
        let harukas = Self.makeModel(server, userID: Self.haruka)
        let observingMine = Task { await mine.observe() }
        let observingHarukas = Task { await harukas.observe() }
        defer {
            observingMine.cancel()
            observingHarukas.cancel()
        }
        #expect(await RoomModelTests.waitUntilLoaded(mine))
        #expect(await RoomModelTests.waitUntilLoaded(harukas))

        for userID in [Self.haruka, Self.sota, Self.mio] {
            await Self.setReady(true, userID, on: server)
        }
        for model in [mine, harukas] {
            #expect(await AsyncTestSupport.eventually { model.readyHint == .waitingForAll(remaining: 1) })
        }

        await mine.toggleReady()
        #expect(server.rooms[DemoScenario.roomID]?.room.status == .unlocked)
        for model in [mine, harukas] {
            // ルームとメンバーは別の購読なので、両方が届くまで待つ
            #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked && model.readyCount == 4 })
            #expect(model.readyHint == .unlocked)
            #expect(model.gachaButtonState == .ready)
        }

        await Self.setReady(false, Self.sota, on: server)
        for model in [mine, harukas] {
            #expect(await AsyncTestSupport.eventually { model.room?.status == .open && model.readyCount == 3 })
            #expect(model.readyHint == .waitingForAll(remaining: 1))
            #expect(model.gachaButtonState == .waiting)
        }
    }

    // MARK: - 強制解禁

    /// 作成者は `open` のときに「強制解禁（作成者）」を押せ、確認の「解禁する」で `forceUnlock` を送る。
    /// 全員の画面が「作成者が解禁しました」になり、準備OKを取り消しても `open` に戻らない
    @Test
    func ownerForceUnlocksAfterConfirmation() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        let mine = Self.makeModel(server, functions: functions)
        let harukas = Self.makeModel(server, userID: Self.haruka)
        let observingMine = Task { await mine.observe() }
        let observingHarukas = Task { await harukas.observe() }
        defer {
            observingMine.cancel()
            observingHarukas.cancel()
        }
        #expect(await RoomModelTests.waitUntilLoaded(mine))
        #expect(await RoomModelTests.waitUntilLoaded(harukas))
        #expect(mine.canForceUnlock)

        mine.forceUnlockTapped()
        #expect(mine.isConfirmingForceUnlock)
        #expect(functions.forceUnlockRequests.isEmpty)

        mine.isConfirmingForceUnlock = false
        await mine.forceUnlock()
        #expect(functions.forceUnlockRequests == [RoomRequest(roomId: DemoScenario.roomID)])
        for model in [mine, harukas] {
            #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })
            #expect(model.readyHint == .forcedUnlocked)
            #expect(model.gachaButtonState == .ready)
            #expect(!model.canForceUnlock)
        }

        await Self.setReady(true, Self.sota, on: server)
        await Self.setReady(false, Self.sota, on: server)
        #expect(server.rooms[DemoScenario.roomID]?.room.status == .unlocked)
        #expect(mine.readyHint == .forcedUnlocked)
    }

    /// 作成者以外には強制解禁を出さず、押す・送る操作をしても送らない（F-30〜32 の AC）
    @Test
    func nonOwnerCannotForceUnlock() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        let harukas = Self.makeModel(server, functions: functions, userID: Self.haruka)
        let observing = Task { await harukas.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(harukas))

        #expect(!harukas.isOwner)
        #expect(!harukas.canForceUnlock)
        #expect(harukas.showsReadyButton)
        harukas.forceUnlockTapped()
        #expect(!harukas.isConfirmingForceUnlock)
        await harukas.forceUnlock()
        #expect(functions.forceUnlockRequests.isEmpty)
    }

    /// 送っている途中は二重に送らず、確認のダイアログも出さない。終わったら購読の値で解禁の表示になる
    @Test
    func forceUnlockIsNotSentTwice() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.forceUnlockBehavior = .suspend
        let model = Self.makeModel(server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.confirmForceUnlockTapped()
        model.confirmForceUnlockTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        #expect(model.isForceUnlocking)
        model.forceUnlockTapped()
        #expect(!model.isConfirmingForceUnlock)
        await model.forceUnlock()
        #expect(functions.forceUnlockRequests.count == 1)

        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isForceUnlocking && model.room?.status == .unlocked })
        #expect(functions.forceUnlockRequests.count == 1)
    }

    /// 通信エラーなら `AppError` の文言のトーストを出し、未解禁のまま、もう一度押せる
    @Test
    func forceUnlockFailureShowsToast() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        let failure = AppError(.network, code: .unavailable)
        functions.forceUnlockBehavior = .fail(failure)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        await model.forceUnlock()
        #expect(toasts.current?.text == failure.message)
        #expect(!model.isForceUnlocking)
        #expect(model.room?.status == .open)
        #expect(model.canForceUnlock)
    }
}
