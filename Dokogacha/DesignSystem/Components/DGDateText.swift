//
//  DGDateText.swift
//  Dokogacha
//
//  部品に出す日付の文言（`04_design_system.md` の §4 の Stamp「日付 M.DD」・03 の S-02 の TicketStub「日付」）。
//

import Foundation

/// 部品に出す日付を、資料の書式の文字列にする。
///
/// 書式は資料で日本の書き方に決まっている（ローカライズで変えない）ので、`DateFormatter` を使わずに暦の値から組み立てる。
/// どのタイムゾーンの暦で読むかは呼び出し側で渡す（部品では `EnvironmentValues.timeZone`）。
nonisolated enum DGDateText {
    /// 「8/24」の形（月と日。どちらも 0 で埋めない）。思い出のきっぷの日付に使う
    /// - Parameters:
    ///   - date: 日時
    ///   - timeZone: 暦を読むタイムゾーン
    static func monthDay(_ date: Date, timeZone: TimeZone) -> String {
        let (month, day) = monthAndDay(date, timeZone: timeZone)
        return "\(month)/\(day)"
    }

    /// 「10.21」「8.04」の形（04 の §4 の `M.DD`。日だけ 2 桁に 0 で埋める）。決定スタンプの日付に使う
    /// - Parameters:
    ///   - date: 日時
    ///   - timeZone: 暦を読むタイムゾーン
    static func stampDate(_ date: Date, timeZone: TimeZone) -> String {
        let (month, day) = monthAndDay(date, timeZone: timeZone)
        let paddedDay = day < 10 ? "0\(day)" : "\(day)"
        return "\(month).\(paddedDay)"
    }

    /// 「10月21日」の形（VoiceOver で決定スタンプの日付を読むときに使う。`M.DD` は数字の並びとして読まれるため）
    /// - Parameters:
    ///   - date: 日時
    ///   - timeZone: 暦を読むタイムゾーン
    static func monthDayJapanese(_ date: Date, timeZone: TimeZone) -> String {
        let (month, day) = monthAndDay(date, timeZone: timeZone)
        return "\(month)月\(day)日"
    }

    /// グレゴリオ暦で読んだ月と日
    private static func monthAndDay(_ date: Date, timeZone: TimeZone) -> (month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.month, .day], from: date)
        return (components.month ?? 0, components.day ?? 0)
    }
}
