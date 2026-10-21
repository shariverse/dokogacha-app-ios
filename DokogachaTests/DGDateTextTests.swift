//
//  DGDateTextTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 部品に出す日付の文言（`DGDateText`）を確かめる。
struct DGDateTextTests {
    /// 日本時間
    nonisolated static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    /// 日本時間の年月日時分から日時を作る
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar.date(from: components))
    }

    /// 思い出のきっぷの日付は「M/D」（0 で埋めない）
    @Test
    func monthDayHasNoPadding() throws {
        #expect(DGDateText.monthDay(try Self.date(2026, 8, 24), timeZone: Self.tokyo) == "8/24")
        #expect(DGDateText.monthDay(try Self.date(2026, 1, 5), timeZone: Self.tokyo) == "1/5")
        #expect(DGDateText.monthDay(try Self.date(2026, 12, 31), timeZone: Self.tokyo) == "12/31")
    }

    /// 決定スタンプの日付は「M.DD」（日だけ 2 桁）
    @Test
    func stampDatePadsDay() throws {
        #expect(DGDateText.stampDate(try Self.date(2026, 10, 21), timeZone: Self.tokyo) == "10.21")
        #expect(DGDateText.stampDate(try Self.date(2026, 8, 4), timeZone: Self.tokyo) == "8.04")
    }

    /// 日付は渡したタイムゾーンの暦で読む（日本時間の 0 時台は、UTC ではまだ前の日）
    @Test
    func usesGivenTimeZone() throws {
        let earlyMorning = try Self.date(2026, 10, 21, hour: 0, minute: 30)
        #expect(DGDateText.monthDay(earlyMorning, timeZone: Self.tokyo) == "10/21")
        #expect(DGDateText.monthDay(earlyMorning, timeZone: .gmt) == "10/20")
        #expect(DGDateText.stampDate(earlyMorning, timeZone: .gmt) == "10.20")
    }
}
