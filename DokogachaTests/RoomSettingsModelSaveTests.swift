//
//  RoomSettingsModelSaveTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-12 の締切日時（範囲の計算し直し）と、保存（`updateRoomSettings`）・失敗のトースト・二重送信の防止を確かめる
extension RoomSettingsModelTests {
    // MARK: - 締切日時

    /// 条件を「締切日時」に変えると、ピッカーを出し、締切日時（初期値は 3 日後の 21:00）と一緒に送る
    @Test
    func switchingToDeadlineSendsDefaultDeadline() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.unlockRule = .deadline
        #expect(model.showsDeadlinePicker)
        let expected = try #require(Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 21)))
        #expect(model.deadline == expected)
        #expect(model.request == UpdateRoomSettingsRequest(
            roomId: DemoScenario.roomID,
            unlockRule: .deadline,
            deadlineAt: CallableTime.milliseconds(from: expected)
        ))
    }

    /// 今の締切日時は、触らなければ範囲の外（もうすぐ）でも変えずに送らない。触ったら範囲の中の値を送る
    @Test
    func untouchedDeadlineIsKeptAndNotSent() async throws {
        let soon = try Self.now().addingTimeInterval(30 * 60)
        let fixture = try Self.make { server in
            server.rooms[DemoScenario.roomID]?.room.settings.unlockRule = .deadline
            server.rooms[DemoScenario.roomID]?.room.settings.deadlineAt = soon
        }
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        #expect(model.deadline == soon)
        model.refreshDeadlineRange()
        #expect(model.deadline == soon)
        #expect(model.request == nil)

        let later = try Self.now().addingTimeInterval(2 * 60 * 60)
        model.deadline = later
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, deadlineAt: CallableTime.milliseconds(from: later)))
    }

    /// 画面を開いたまま時間がたっても、保存の直前に範囲を計算し直し、下限を割った締切日時を新しい下限に上げて送る（断られない）
    @Test
    func saveRefreshesDeadlineRange() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.unlockRule = .deadline
        model.deadline = model.deadlineRange.lowerBound
        fixture.clock.advance(by: 30 * 60)
        await model.save()

        let request = try #require(fixture.functions.updateRequests.first)
        let sent = CallableTime.date(fromMilliseconds: try #require(request.deadlineAt))
        #expect(sent == fixture.clock.now.addingTimeInterval(60 * 60))
        #expect(model.didSave)
        #expect(fixture.room?.settings.unlockRule == .deadline)
        #expect(fixture.toasts.current == nil)
    }

    /// 前面に戻ったとき（`refreshDeadlineRange`）も、触った締切日時を新しい範囲に収める
    @Test
    func refreshDeadlineRangeClampsEditedDeadline() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.unlockRule = .deadline
        model.deadline = model.deadlineRange.lowerBound
        fixture.clock.advance(by: 2 * 60 * 60)
        model.refreshDeadlineRange()
        #expect(model.deadlineRange == RoomDeadline.selectableRange(now: fixture.clock.now))
        #expect(model.deadline == fixture.clock.now.addingTimeInterval(60 * 60))
    }

    // MARK: - 保存

    /// 投稿数を上げて保存すると、変えた項目だけを送り、ルームの設定が変わり、`didSave` が立つ（F-03）
    @Test
    func saveRaisesPostLimit() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.postLimit = 5
        model.likeMode = .equal
        model.saveTapped()
        #expect(await AsyncTestSupport.eventually { model.didSave })

        #expect(fixture.functions.updateRequests == [
            UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, postLimit: 5, likeMode: .equal)
        ])
        #expect(fixture.room?.settings.postLimit == 5)
        #expect(fixture.room?.settings.likeMode == .equal)
        #expect(!model.canSave)
        #expect(fixture.toasts.current == nil)
    }

    /// サーバーに断られたら（解禁の条件は候補募集中のときだけ）、その理由の文言のトーストを出し、入力を残してもう一度押せる
    @Test
    func rejectionShowsReasonAndKeepsInput() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let reason = AppError.Reason.unlockRuleLocked.rawValue
        fixture.functions.updateBehavior = .fail(ServerFailure(code: .failedPrecondition, reason: reason))
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.unlockRule = .majority
        await model.save()
        #expect(fixture.toasts.current?.text == "解禁の条件は候補募集中のときだけ変更できます")
        #expect(!model.didSave)
        #expect(model.unlockRule == .majority)
        #expect(model.canSave)
    }

    /// 通信エラーではトースト「通信できませんでした」を出す。cancel のエラーではトーストを出さない
    @Test
    func networkFailureShowsToastButCancelDoesNot() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        fixture.functions.updateBehavior = .fail(ServerFailure(code: .unavailable))
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.postLimit = 4
        await model.save()
        #expect(fixture.toasts.current?.text == "通信できませんでした")

        fixture.toasts.dismiss()
        fixture.functions.updateBehavior = .fail(CancellationError())
        await model.save()
        #expect(fixture.toasts.current == nil)
    }

    /// 保存を送っている途中は、もう一度押しても送らない（二重送信の防止）。入力も変えられない
    @Test
    func preventsDoubleSave() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        fixture.functions.updateBehavior = .suspend
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.postLimit = 4
        model.saveTapped()
        model.saveTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        #expect(model.isSaving)
        #expect(!model.canSave)
        #expect(!model.isNameEditable)
        await model.save()
        #expect(fixture.functions.updateRequests.count == 1)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.didSave })
        #expect(fixture.functions.updateRequests.count == 1)
    }

    /// 画面が消えたら送っている途中の保存を止め、結果が返っても `didSave` を立てず、トーストも出さない
    @Test
    func cancelSaveStopsWithoutToast() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        fixture.functions.updateBehavior = .suspend
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.postLimit = 4
        model.saveTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        model.cancelSave()
        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isSaving })
        #expect(!model.didSave)
        #expect(fixture.toasts.current == nil)
    }

    /// ルームが無くなったら（削除された）シートを閉じる
    @Test
    func closesWhenRoomIsGone() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }
        #expect(!model.shouldClose)

        fixture.server.rooms[DemoScenario.roomID] = nil
        #expect(await AsyncTestSupport.eventually { model.shouldClose })
    }
}
