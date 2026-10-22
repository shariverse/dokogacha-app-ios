//
//  SendingLockTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 送っている途中に戻らせない・押せなくなった確認のダイアログを閉じる（PR #49・#55・#61 の持ち越し）を確かめる
struct SendingLockTests {
    /// 送っている途中の画面が 1 つでもあれば、戻らせない。外れたら戻れる
    @Test
    func navigationLockHoldsWhileAnyScreenIsSending() {
        let lock = NavigationLock()
        let first = UUID()
        let second = UUID()
        #expect(!lock.isLocked)
        lock.set(first, locked: true)
        lock.set(second, locked: true)
        lock.set(first, locked: false)
        #expect(lock.isLocked)
        lock.set(second, locked: false)
        #expect(!lock.isLocked)
        // 外したものを外し直しても変わらない
        lock.set(second, locked: false)
        #expect(!lock.isLocked)
    }

    /// 強制解禁は、確認で押した時点から送っている途中として扱い（戻る操作を止める）、通った後は購読が追いつく前でも押せない
    @Test
    func forceUnlockLocksFromTapAndStaysHiddenAfterSuccess() async {
        let server = RoomModelReadyTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.forceUnlockBehavior = .suspend
        let model = RoomModelReadyTests.makeModel(server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.confirmForceUnlockTapped()
        // Task が動き出す前から送っている途中
        #expect(model.isSendingForceUnlock)
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isSendingForceUnlock })
        #expect(model.hasForceUnlocked)
        #expect(!model.canForceUnlock)
    }

    /// 強制解禁の確認を出している間に、ほかの操作で解禁されたら、ダイアログを閉じる
    @Test
    func forceUnlockConfirmationClosesWhenUnavailable() async throws {
        let server = RoomModelReadyTests.makeServer()
        let model = RoomModelReadyTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.forceUnlockTapped()
        #expect(model.isConfirmingForceUnlock)
        // 押せるうちは閉じない
        model.closeUnavailableConfirmation()
        #expect(model.isConfirmingForceUnlock)

        // 作成者が別の端末で解禁した
        try await server.forceUnlock(RoomRequest(roomId: DemoScenario.roomID))
        #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })
        model.closeUnavailableConfirmation()
        #expect(!model.isConfirmingForceUnlock)
    }

    /// 削除の確認で押した時点から送っている途中として扱う（Task が動き出す前に閉じられない）
    @Test
    func deleteLocksFromTap() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .suspend
        let model = CandidateDetailModelTests.makeModel(CandidateDetailModelTests.mine, server: server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await CandidateDetailModelTests.waitUntilLoaded(model))

        model.confirmDeleteTapped()
        #expect(model.isSending)
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        functions.finish()
        #expect(await AsyncTestSupport.eventually { model.didDelete })
        #expect(!model.isSending)
    }

    /// 削除の確認を出している間にガチャが回されて削除できなくなったら、ダイアログを閉じて理由をトーストで出す
    @Test
    func deleteConfirmationClosesWhenRoomIsDecided() async throws {
        let server = RoomModelTests.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = CandidateDetailModelTests.makeModel(CandidateDetailModelTests.mine, server: server, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await CandidateDetailModelTests.waitUntilLoaded(model))

        model.deleteTapped()
        #expect(model.isConfirmingDelete)
        try await server.forceUnlock(RoomRequest(roomId: DemoScenario.roomID))
        _ = try await server.drawGacha(RoomRequest(roomId: DemoScenario.roomID))
        #expect(await AsyncTestSupport.eventually { model.room.room?.status == .drawn })
        #expect(!model.canDelete)

        model.closeUnavailableConfirmation()
        #expect(!model.isConfirmingDelete)
        #expect(toasts.current?.text == "このルームはもう行き先が決まっています")
    }
}
