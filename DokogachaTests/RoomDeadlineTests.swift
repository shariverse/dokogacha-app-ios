//
//  RoomDeadlineTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ルーム作成（F-02）の締切日時の範囲（今から 1 時間後〜30 日後）と初期値（3 日後の 21:00）を確かめる
struct RoomDeadlineTests {
    /// 日本時間のグレゴリオ暦
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }

    /// 日本時間の 2026 年の月日時分から日時を作る
    static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar.date(from: components))
    }

    /// 範囲は今から 1 時間後〜30 日後
    @Test
    func selectableRangeIsOneHourToThirtyDays() throws {
        let now = try Self.date(10, 22, 12)
        let range = RoomDeadline.selectableRange(now: now)
        #expect(range.lowerBound == now.addingTimeInterval(60 * 60))
        #expect(range.upperBound == now.addingTimeInterval(30 * 24 * 60 * 60))
    }

    /// 初期値は暦の上で 3 日後の 21:00（今の時刻によらない）
    @Test(arguments: [(0, 0), (12, 0), (21, 30), (23, 59)])
    func defaultIsThreeDaysLaterAtNine(time: (hour: Int, minute: Int)) throws {
        let now = try Self.date(10, 22, time.hour, time.minute)
        let deadline = RoomDeadline.defaultDeadline(now: now, calendar: Self.calendar)
        #expect(deadline == (try Self.date(10, 25, 21)))
        #expect(RoomDeadline.selectableRange(now: now).contains(deadline))
    }

    /// 月をまたいでも 3 日後の 21:00
    @Test
    func defaultCrossesMonth() throws {
        let now = try Self.date(10, 30, 9)
        #expect(RoomDeadline.defaultDeadline(now: now, calendar: Self.calendar) == (try Self.date(11, 2, 21)))
    }

    /// 範囲の外の日時は範囲の端に収める
    @Test
    func clampsIntoRange() throws {
        let now = try Self.date(10, 22, 12)
        let range = RoomDeadline.selectableRange(now: now)
        #expect(RoomDeadline.clamped(now, to: range) == range.lowerBound)
        #expect(RoomDeadline.clamped(now.addingTimeInterval(31 * 24 * 60 * 60), to: range) == range.upperBound)
        let inside = now.addingTimeInterval(2 * 60 * 60)
        #expect(RoomDeadline.clamped(inside, to: range) == inside)
    }
}
