//
//  RelativeTimeTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 候補の経過時間（F-12）の区分と表記を確かめる（06 の §2 の「経過時間」）。
///
/// サーバーでは経過時間を使わないので、TypeScript 側のテストは無い（`RelativeTime.swift` の冒頭を参照）。
struct RelativeTimeTests {
    /// 日本時間
    nonisolated static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    /// 日本時間のグレゴリオ暦
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar
    }

    /// 日本時間の年月日時分秒から日時を作る
    static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) throws -> Date {
        let components = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second)
        return try #require(calendar.date(from: components))
    }

    /// 今の時刻（2026-10-22 12:00 日本時間）
    static func now() throws -> Date {
        try date(10, 22, 12)
    }

    /// `now` の `seconds` 秒前の表記
    static func text(secondsAgo seconds: TimeInterval) throws -> String {
        let now = try now()
        return RelativeTime.text(since: now.addingTimeInterval(-seconds), now: now, calendar: calendar)
    }

    // MARK: 06 の §2 のケース

    /// 59 秒は「たった今」、1 分は「1分前」
    @Test
    func justNowAndMinutes() throws {
        #expect(try Self.text(secondsAgo: 0) == "たった今")
        #expect(try Self.text(secondsAgo: 59) == "たった今")
        #expect(try Self.text(secondsAgo: 60) == "1分前")
        #expect(try Self.text(secondsAgo: 59 * 60 + 59) == "59分前")
    }

    /// 1 時間は「1時間前」、23 時間は「23時間前」（暦の上で前の日でも 24 時間未満なら時間で出す）
    @Test
    func hours() throws {
        #expect(try Self.text(secondsAgo: 60 * 60) == "1時間前")
        #expect(try Self.text(secondsAgo: 23 * 60 * 60) == "23時間前")
        #expect(try Self.text(secondsAgo: 24 * 60 * 60 - 1) == "23時間前")
    }

    /// 前の日（24 時間以上前）は「昨日」
    @Test
    func yesterday() throws {
        let now = try Self.now()
        #expect(RelativeTime.text(since: try Self.date(10, 21, 12), now: now, calendar: Self.calendar) == "昨日")
        #expect(RelativeTime.text(since: try Self.date(10, 21, 0, 0), now: now, calendar: Self.calendar) == "昨日")
    }

    /// 暦の上で 2 日前からは「◯日前」、6 日前は「6日前」
    @Test
    func days() throws {
        let now = try Self.now()
        #expect(RelativeTime.text(since: try Self.date(10, 20, 23, 59), now: now, calendar: Self.calendar) == "2日前")
        #expect(RelativeTime.text(since: try Self.date(10, 16, 12), now: now, calendar: Self.calendar) == "6日前")
        #expect(RelativeTime.text(since: try Self.date(10, 16, 0, 0), now: now, calendar: Self.calendar) == "6日前")
    }

    /// 7 日前からは「M/D」（0 で埋めない）
    @Test
    func monthDayFromSevenDays() throws {
        let now = try Self.now()
        #expect(RelativeTime.text(since: try Self.date(10, 15, 12), now: now, calendar: Self.calendar) == "10/15")
        #expect(RelativeTime.text(since: try Self.date(10, 15, 23, 59), now: now, calendar: Self.calendar) == "10/15")
        #expect(RelativeTime.text(since: try Self.date(8, 4, 9), now: now, calendar: Self.calendar) == "8/4")
    }

    // MARK: 区分

    /// 区分の値（画面の側でもこれを使って表記を作れる）
    @Test
    func elapsedCases() throws {
        let now = try Self.now()
        let calendar = Self.calendar
        #expect(RelativeTime.elapsed(since: now.addingTimeInterval(-30), now: now, calendar: calendar) == .justNow)
        #expect(RelativeTime.elapsed(since: now.addingTimeInterval(-5 * 60), now: now, calendar: calendar) == .minutes(5))
        #expect(RelativeTime.elapsed(since: now.addingTimeInterval(-5 * 3_600), now: now, calendar: calendar) == .hours(5))
        #expect(RelativeTime.elapsed(since: try Self.date(10, 19, 12), now: now, calendar: calendar) == .days(3))
        let old = try Self.date(10, 1, 12)
        #expect(RelativeTime.elapsed(since: old, now: now, calendar: calendar) == .date(old))
    }

    /// 投稿日時が未来（端末の時計のずれ）でも「たった今」
    @Test
    func futureIsJustNow() throws {
        #expect(try Self.text(secondsAgo: -3_600) == "たった今")
    }

    /// 日付の差は渡した暦のタイムゾーンで数える（日本時間の 10/22 0:30 から見て 10/20 23:00 は 2 日前、UTC では 10/21 と 10/20 で昨日）
    @Test
    func usesCalendarTimeZone() throws {
        let now = try Self.date(10, 22, 0, 30)
        let posted = try Self.date(10, 20, 23, 0)
        #expect(RelativeTime.text(since: posted, now: now, calendar: Self.calendar) == "2日前")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        #expect(RelativeTime.text(since: posted, now: now, calendar: utc) == "昨日")
    }
}
