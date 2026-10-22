//
//  RoomDeadlineTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ルーム作成（F-02）・ルーム設定（F-03）の締切日時の範囲（今から 1 時間後〜30 日後の 5 分前）と初期値（3 日後の 21:00）、
/// 範囲の計算し直し（`DeadlineSelection`）を確かめる
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

    /// 範囲は今から 1 時間後〜30 日後の 5 分前（上限は端末の時計のずれの分だけ手前。サーバーの上限には猶予が無いため）
    @Test
    func selectableRangeIsOneHourToThirtyDaysMinusMargin() throws {
        let now = try Self.date(10, 22, 12)
        let range = RoomDeadline.selectableRange(now: now)
        #expect(range.lowerBound == now.addingTimeInterval(60 * 60))
        #expect(range.upperBound == now.addingTimeInterval(30 * 24 * 60 * 60 - 5 * 60))
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

    // MARK: - 初期値のフォールバック

    /// 暦で 21:00 を作れなかった（夏時間で無い日など）ときは、範囲の下限にする
    @Test
    func defaultFallsBackToLowerBoundWhenCandidateMissing() throws {
        let range = RoomDeadline.selectableRange(now: try Self.date(10, 22, 12))
        #expect(RoomDeadline.defaultDeadline(candidate: nil, in: range) == range.lowerBound)
    }

    /// 作った初期値が範囲の外なら、範囲の端に収める（範囲の中ならそのまま）
    @Test
    func defaultCandidateIsClampedIntoRange() throws {
        let now = try Self.date(10, 22, 12)
        let range = RoomDeadline.selectableRange(now: now)
        #expect(RoomDeadline.defaultDeadline(candidate: now, in: range) == range.lowerBound)
        #expect(RoomDeadline.defaultDeadline(candidate: now.addingTimeInterval(40 * 24 * 60 * 60), in: range) == range.upperBound)
        let inside = try Self.date(10, 25, 21)
        #expect(RoomDeadline.defaultDeadline(candidate: inside, in: range) == inside)
    }

    // MARK: - 範囲の計算し直し

    /// 範囲を計算し直すと、下限を割った日時は新しい下限に上がる（画面を開いたまま時間がたったとき）
    @Test
    func refreshMovesDateUpToNewLowerBound() throws {
        let opened = try Self.date(10, 22, 12)
        var selection = DeadlineSelection(date: opened.addingTimeInterval(60 * 60), now: opened)
        #expect(selection.isInRange)

        let later = opened.addingTimeInterval(30 * 60)
        selection.refreshRange(now: later)
        // 範囲だけを計算し直すと、日時は変えずに範囲の外になる
        #expect(selection.date == opened.addingTimeInterval(60 * 60))
        #expect(!selection.isInRange)

        selection.refresh(now: later)
        #expect(selection.range == RoomDeadline.selectableRange(now: later))
        #expect(selection.date == later.addingTimeInterval(60 * 60))
        #expect(selection.isInRange)
    }

    /// 範囲の中の日時は、計算し直しても変えない
    @Test
    func refreshKeepsDateInsideRange() throws {
        let opened = try Self.date(10, 22, 12)
        let chosen = try Self.date(10, 25, 21)
        var selection = DeadlineSelection(date: chosen, now: opened)
        selection.refresh(now: opened.addingTimeInterval(2 * 60 * 60))
        #expect(selection.date == chosen)
    }

    /// 最初に渡した日時は、範囲の外でもそのまま持つ（S-12 の今の締切日時を変えずに残すため）
    @Test
    func initKeepsDateOutsideRange() throws {
        let now = try Self.date(10, 22, 12)
        let soon = now.addingTimeInterval(10 * 60)
        let selection = DeadlineSelection(date: soon, now: now)
        #expect(selection.date == soon)
        #expect(!selection.isInRange)
    }
}
