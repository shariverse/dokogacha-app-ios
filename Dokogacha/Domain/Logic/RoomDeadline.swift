//
//  RoomDeadline.swift
//  Dokogacha
//
//  ルーム作成（F-02）・ルーム設定（F-03）の締切日時の、選べる範囲と初期値。
//

import Foundation

/// 締切日時（解禁の条件が「締切日時」のとき。02 の §2.2「現在から1時間後〜30日後」「初期値 3日後の21:00」）の決まり。
///
/// 時刻（`now`）と暦（`calendar`。タイムゾーンを含む）は呼び出し側から渡す（テストで固定するため）。
/// サーバー（`createRoom` の `parseCreateRoomInput`・`updateRoomSettings` の `planUnlockRule`）は、
/// サーバーの時刻で「1 時間後（5 分の猶予）〜30 日後」を確かめる。下限には猶予があるが上限には無いので、
/// 画面の範囲は上限だけを `latestMargin` だけ手前にする（端末の時計が進んでいても、上限ちょうどを選んで断られないように）。
nonisolated enum RoomDeadline {
    /// 上限（30 日後）を手前にする幅（端末の時計のずれの猶予。backend の下限の猶予 `DEADLINE_EARLIEST_GRACE_MS` と同じ 5 分）
    static let latestMargin: TimeInterval = 5 * 60

    /// 選べる範囲（今から 1 時間後〜30 日後の 5 分前。両端を含む）
    /// - Parameter now: 今の時刻（範囲を計算し直すたびに、そのときの時刻を渡す）
    static func selectableRange(now: Date) -> ClosedRange<Date> {
        now.addingTimeInterval(DomainConstants.Limits.deadlineEarliestFromNow)
            ... now.addingTimeInterval(DomainConstants.Limits.deadlineLatestFromNow - latestMargin)
    }

    /// 初期値（暦の上で 3 日後の 21:00:00）。
    ///
    /// 3 日後の 21:00 は必ず範囲に入る（最も早くても 2 日と 21 時間後・最も遅くても 4 日後より前）が、
    /// 夏時間などで 21:00 が無い日に備えて、作れなければ・範囲を外れたら範囲の中に収める（`defaultDeadline(candidate:in:)`）。
    /// - Parameters:
    ///   - now: 今の時刻
    ///   - calendar: 暦（端末のタイムゾーン）
    static func defaultDeadline(now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let candidate = calendar
            .date(byAdding: .day, value: DomainConstants.Limits.defaultDeadlineDaysLater, to: startOfToday)
            .flatMap { day in
                calendar.date(bySettingHour: DomainConstants.Limits.defaultDeadlineHour, minute: 0, second: 0, of: day)
            }
        return defaultDeadline(candidate: candidate, in: selectableRange(now: now))
    }

    /// 暦から作った初期値の候補を、範囲に合わせて決める。作れなかった（nil）なら範囲の下限、範囲の外なら端に収める
    /// - Parameters:
    ///   - candidate: 暦で作った「3 日後の 21:00」（作れなければ nil）
    ///   - range: 選べる範囲
    static func defaultDeadline(candidate: Date?, in range: ClosedRange<Date>) -> Date {
        guard let candidate else {
            return range.lowerBound
        }
        return clamped(candidate, to: range)
    }

    /// 範囲の中に収めた日時
    static func clamped(_ date: Date, to range: ClosedRange<Date>) -> Date {
        min(max(date, range.lowerBound), range.upperBound)
    }
}

/// 画面で選んでいる締切日時と、選べる範囲（S-03・S-12 で共通）。
///
/// 範囲は「今」から決まるので、画面を開いたときの範囲のままにすると、時間がたってから送ったときに
/// 下限（1 時間後）を割ってサーバーに断られる。画面は **送る直前** と **前面に戻ったとき** に `refresh(now:)` を呼び、
/// 範囲を計算し直して、範囲の外になった日時を範囲の中に収める。
nonisolated struct DeadlineSelection: Equatable, Sendable {
    /// 選べる範囲（最後に計算し直した時刻から決めたもの。日時ピッカーの範囲）
    private(set) var range: ClosedRange<Date>
    /// 選んでいる日時
    var date: Date

    /// - Parameters:
    ///   - date: 最初に選んでおく日時（範囲の外でもそのまま持つ。S-12 では今の締切日時を変えずに残すため）
    ///   - now: 今の時刻
    init(date: Date, now: Date) {
        range = RoomDeadline.selectableRange(now: now)
        self.date = date
    }

    /// 選んでいる日時が範囲の中か（送ってよいか）
    var isInRange: Bool {
        range.contains(date)
    }

    /// 範囲を今の時刻で計算し直し、範囲の外になった日時を範囲の中に収める
    /// - Parameter now: 今の時刻
    mutating func refresh(now: Date) {
        refreshRange(now: now)
        date = RoomDeadline.clamped(date, to: range)
    }

    /// 範囲だけを今の時刻で計算し直す（選んでいる日時は変えない。S-12 で、まだ触っていない今の締切日時を変えないため）
    /// - Parameter now: 今の時刻
    mutating func refreshRange(now: Date) {
        range = RoomDeadline.selectableRange(now: now)
    }
}
