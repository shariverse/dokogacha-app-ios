//
//  RelativeTime.swift
//  Dokogacha
//
//  候補の経過時間（02 の §3.3・F-12）の区分と表記。
//  サーバーでは使わない（通知の文面に経過時間は無い）ので、TypeScript 側には持たない。
//

import Foundation

/// 投稿からの経過時間の区分（F-12「たった今／◯分前／◯時間前／昨日／◯日前（7日以上は M/D）」）。
nonisolated enum ElapsedTime: Equatable, Sendable {
    /// 1 分未満（端末の時計がずれていて投稿日時が未来のときも含む）
    case justNow
    /// 1〜59 分前
    case minutes(Int)
    /// 1〜23 時間前
    case hours(Int)
    /// 24 時間以上前で、暦の上で前の日
    case yesterday
    /// 暦の上で 2〜6 日前
    case days(Int)
    /// 暦の上で 7 日以上前（投稿日時を「M/D」で出す）
    case date(Date)
}

/// 経過時間の区分と表記。
///
/// 時刻（`now`）と暦（`calendar`。タイムゾーンを含む）は呼び出し側から渡す（テストで固定するため）。
/// 「◯時間前」までは経過した秒数で、「昨日」からは暦の日付の差で決める（「昨日」は 24 時間前ではなく前の日のこと）。
/// 24 時間未満なら、暦の上で前の日でも「◯時間前」にする（06 の §2「23時間「23時間前」」）。
nonisolated enum RelativeTime {
    /// 1 分の秒数
    private static let secondsPerMinute: TimeInterval = 60
    /// 1 時間の秒数
    private static let secondsPerHour: TimeInterval = 60 * 60
    /// 1 日の秒数
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
    /// 「M/D」に切り替える暦の日数の差（02 の §3.3「7日以上は M/D」）
    private static let monthDayFromDays = 7

    /// 投稿日時からの経過時間の区分を返す。
    /// - Parameters:
    ///   - date: 投稿日時
    ///   - now: 今の時刻
    ///   - calendar: 日付の差を数える暦（タイムゾーンを含む）
    static func elapsed(since date: Date, now: Date, calendar: Calendar) -> ElapsedTime {
        let seconds = now.timeIntervalSince(date)
        if seconds < secondsPerMinute {
            return .justNow
        }
        if seconds < secondsPerHour {
            return .minutes(Int(seconds / secondsPerMinute))
        }
        if seconds < secondsPerDay {
            return .hours(Int(seconds / secondsPerHour))
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days <= 1 {
            return .yesterday
        }
        if days < monthDayFromDays {
            return .days(days)
        }
        return .date(date)
    }

    /// 経過時間の表記（03 の S-07 の CandidateCard「みさきさんの投稿 · 3日前」の「3日前」の部分）。
    ///
    /// 文言はローカライズできる形（`String(localized:)`）で持つ。「M/D」は部品の日付の書式（`DGDateText.monthDay`）を使い、書式を二重に持たない。
    /// - Parameters:
    ///   - elapsed: 経過時間の区分
    ///   - timeZone: 「M/D」を読むタイムゾーン
    static func text(_ elapsed: ElapsedTime, timeZone: TimeZone) -> String {
        switch elapsed {
        case .justNow: String(localized: "たった今")
        case let .minutes(minutes): String(localized: "\(minutes)分前")
        case let .hours(hours): String(localized: "\(hours)時間前")
        case .yesterday: String(localized: "昨日")
        case let .days(days): String(localized: "\(days)日前")
        case let .date(date): DGDateText.monthDay(date, timeZone: timeZone)
        }
    }

    /// 投稿日時からの経過時間の表記を返す（`elapsed(since:now:calendar:)` と `text(_:timeZone:)` をまとめたもの）。
    /// - Parameters:
    ///   - date: 投稿日時
    ///   - now: 今の時刻
    ///   - calendar: 日付の差を数える暦（「M/D」もこの暦のタイムゾーンで読む）
    static func text(since date: Date, now: Date, calendar: Calendar) -> String {
        text(elapsed(since: date, now: now, calendar: calendar), timeZone: calendar.timeZone)
    }
}
