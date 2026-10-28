//
//  ReadyHintTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-07 のヒント文言の選び方（`ReadyHint`。02 の §5.2）。解禁の文言はルームの `status` が `unlocked` のときだけ出すこと
struct ReadyHintTests {
    nonisolated static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
    nonisolated static let japanese = Locale(identifier: "ja_JP")

    /// 東京の暦で作った日時
    static func tokyoDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.tokyo
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    static func hint(
        _ status: RoomStatus,
        rule: UnlockRule = .all,
        members: Int = 5,
        ready: Int = 0,
        deadlineAt: Date? = nil,
        forced: Bool = false
    ) -> ReadyHint? {
        ReadyHint.make(UnlockInput(
            status: status,
            rule: rule,
            memberCount: members,
            readyCount: ready,
            deadlineAt: deadlineAt,
            forcedUnlock: forced
        ))
    }

    /// 全員OK: 4/5 は「あと 1人」・0/5 は「あと 5人」
    @Test
    func allRuleCountsRemaining() {
        #expect(Self.hint(.open, members: 5, ready: 4) == .waitingForAll(remaining: 1))
        #expect(Self.hint(.open, members: 5, ready: 0) == .waitingForAll(remaining: 5))
    }

    /// 過半数OK: 2/4 は「あと 1人」・1/5 は「あと 2人」
    @Test
    func majorityRuleCountsRemaining() {
        #expect(Self.hint(.open, rule: .majority, members: 4, ready: 2) == .waitingForMajority(remaining: 1))
        #expect(Self.hint(.open, rule: .majority, members: 5, ready: 1) == .waitingForMajority(remaining: 2))
    }

    /// 条件に届いていても `status` が `open` の間は解禁の文言にしない（「あと 0人」。サーバーが `unlocked` にするまで）
    @Test
    func openRoomNeverShowsUnlockedText() throws {
        #expect(Self.hint(.open, members: 4, ready: 4) == .waitingForAll(remaining: 0))
        #expect(Self.hint(.open, rule: .majority, members: 4, ready: 4) == .waitingForMajority(remaining: 0))
        // 締切を過ぎても `checkDeadlines`（5 分ごと）が `unlocked` にするまでは締切の文言
        let past = try Self.tokyoDate(2025, 11, 8, 21, 0)
        #expect(Self.hint(.open, rule: .deadline, deadlineAt: past) == .waitingForDeadline(deadlineAt: past))
        // 強制解禁のフラグだけ先に届いても、`open` なら未解禁の文言
        #expect(Self.hint(.open, members: 4, ready: 1, forced: true) == .waitingForAll(remaining: 3))
    }

    /// `unlocked` なら、強制解禁かどうかで文言を選ぶ（準備OKの数・条件によらない）
    @Test
    func unlockedRoomShowsUnlockedText() {
        #expect(Self.hint(.unlocked, members: 4, ready: 4) == .unlocked)
        #expect(Self.hint(.unlocked, rule: .deadline) == .unlocked)
        #expect(Self.hint(.unlocked, members: 4, ready: 0, forced: true) == .forcedUnlocked)
    }

    /// 抽選の後と、締切の無い壊れた「締切日時」のルームはヒントを出さない
    @Test(arguments: [RoomStatus.drawn, .closed])
    func decidedRoomHasNoHint(_ status: RoomStatus) {
        #expect(Self.hint(status) == nil)
        #expect(Self.hint(.open, rule: .deadline, deadlineAt: nil) == nil)
    }

    /// 締切の日時は「11/8(土) 21:00」の形（月・日は 0 で埋めず、時・分は 2 桁）
    @Test
    func deadlineTextFormat() throws {
        let saturday = try Self.tokyoDate(2025, 11, 8, 21, 0)
        #expect(ReadyHint.deadlineText(saturday, timeZone: Self.tokyo, locale: Self.japanese) == "11/8(土) 21:00")
        let monday = try Self.tokyoDate(2026, 1, 5, 9, 5)
        #expect(ReadyHint.deadlineText(monday, timeZone: Self.tokyo, locale: Self.japanese) == "1/5(月) 09:05")
    }

    /// 和暦の端末でも、月と日はグレゴリオ暦で読む（タイムゾーンは渡したもの）
    @Test
    func deadlineTextUsesGregorianInTimeZone() throws {
        let date = try Self.tokyoDate(2026, 1, 1, 0, 30)
        // UTC では 12/31 15:30（水）
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(ReadyHint.deadlineText(date, timeZone: utc, locale: Locale(identifier: "ja_JP@calendar=japanese")) == "12/31(水) 15:30")
    }
}
