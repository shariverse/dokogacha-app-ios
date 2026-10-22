//
//  CreateRoomModelDeadlineTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-03 の締切日時の範囲を、前面に戻ったとき・送る直前に計算し直すこと（`DeadlineSelection`）を確かめる
extension CreateRoomModelTests {
    /// 画面を開いたまま時間がたっても、前面に戻ったときに範囲を計算し直し、下限を割った締切日時を新しい下限に上げる
    @Test
    func refreshDeadlineRangeFollowsClock() throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.unlockRule = .deadline
        model.deadline = model.deadlineRange.lowerBound

        fixture.clock.advance(by: 2 * 60 * 60)
        model.refreshDeadlineRange()
        let now = fixture.clock.now
        #expect(model.deadlineRange == RoomDeadline.selectableRange(now: now))
        #expect(model.deadline == now.addingTimeInterval(60 * 60))
    }

    /// 画面を開いてから時間がたって送っても、送る直前に範囲を計算し直すので、サーバーに断られない締切日時を送る
    @Test
    func submitRefreshesDeadlineRangeBeforeSending() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = "年末の旅行"
        model.unlockRule = .deadline
        model.deadline = model.deadlineRange.lowerBound

        // 下限（1 時間後）からサーバーの猶予（5 分）を超えて時間がたった
        fixture.clock.advance(by: 30 * 60)
        await model.submit()

        let request = try #require(fixture.functions.requests.first)
        let sent = CallableTime.date(fromMilliseconds: try #require(request.deadlineAt))
        #expect(sent == fixture.clock.now.addingTimeInterval(60 * 60))
        #expect(model.createdRoom != nil)
        #expect(fixture.toasts.current == nil)
    }

    /// 上限ちょうどを選んでも、端末の時計がサーバーより少し（5 分まで）進んでいれば断られない
    @Test
    func upperBoundIsAcceptedWithClockAhead() async throws {
        // サーバーの時刻が 4 分遅れている（端末の時計が 4 分進んでいる）
        let fixture = try Self.make(serverOffset: -4 * 60)
        let model = fixture.model
        model.name = "年末の旅行"
        model.unlockRule = .deadline
        model.deadline = model.deadlineRange.upperBound
        await model.submit()
        #expect(model.createdRoom != nil)
        #expect(fixture.toasts.current == nil)
    }
}
