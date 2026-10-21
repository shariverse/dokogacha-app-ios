//
//  RoomDeadline.swift
//  Dokogacha
//
//  ルーム作成（F-02）の締切日時の、選べる範囲と初期値。
//

import Foundation

/// 締切日時（解禁の条件が「締切日時」のとき。02 の §2.2「現在から1時間後〜30日後」「初期値 3日後の21:00」）の決まり。
///
/// 時刻（`now`）と暦（`calendar`。タイムゾーンを含む）は呼び出し側から渡す（テストで固定するため）。
/// サーバー（`createRoom` の `parseCreateRoomInput`）は、下限に 5 分の猶予を持たせて同じ範囲を確かめる。
/// 画面の日時ピッカーの範囲は、ここで決めた猶予なしの範囲にする。
nonisolated enum RoomDeadline {
    /// 選べる範囲（今から 1 時間後〜30 日後。両端を含む）
    /// - Parameter now: 今の時刻（画面を開いた時刻）
    static func selectableRange(now: Date) -> ClosedRange<Date> {
        now.addingTimeInterval(DomainConstants.Limits.deadlineEarliestFromNow)
            ... now.addingTimeInterval(DomainConstants.Limits.deadlineLatestFromNow)
    }

    /// 初期値（暦の上で 3 日後の 21:00:00）。
    ///
    /// 3 日後の 21:00 は必ず範囲に入る（最も早くても 2 日と 21 時間後・最も遅くても 4 日後より前）が、
    /// 夏時間などで 21:00 が無い日に備えて、作れなければ・範囲を外れたら範囲の中に収める。
    /// - Parameters:
    ///   - now: 今の時刻
    ///   - calendar: 暦（端末のタイムゾーン）
    static func defaultDeadline(now: Date, calendar: Calendar) -> Date {
        let range = selectableRange(now: now)
        let startOfToday = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: DomainConstants.Limits.defaultDeadlineDaysLater, to: startOfToday),
              let deadline = calendar.date(
                  bySettingHour: DomainConstants.Limits.defaultDeadlineHour,
                  minute: 0,
                  second: 0,
                  of: day
              ) else {
            return range.lowerBound
        }
        return clamped(deadline, to: range)
    }

    /// 範囲の中に収めた日時
    static func clamped(_ date: Date, to range: ClosedRange<Date>) -> Date {
        min(max(date, range.lowerBound), range.upperBound)
    }
}
