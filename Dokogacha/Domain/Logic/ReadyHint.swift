//
//  ReadyHint.swift
//  Dokogacha
//
//  S-07 のルームパネルのヒント文言（02 の §5.2・F-31）の中身。
//

import Foundation

/// S-07 のルームパネルに出すヒント（02 の §5.2 の「未解禁時のヒント文言」「解禁時」「強制解禁時」）。
///
/// 解禁しているかは**ルームの `status` で決める**（サーバーの `onMemberWrite`・`forceUnlock`・`checkDeadlines` が書く値）。
/// `UnlockJudge` の判定は「あと N人」の人数にだけ使う。締切での解禁は `checkDeadlines` が 5 分ごとにまとめて判定するので、
/// 締切を過ぎてから最大 5 分は判定が「解禁」・`status` が `open` になる。その間に「条件を満たしました」と出すと、
/// ガチャのボタンが押せないまま食い違うので、`status` が `unlocked` になるまでは未解禁の文言のままにする。
nonisolated enum ReadyHint: Equatable, Sendable {
    /// 「条件を満たしました。誰が回してもOK！」
    case unlocked
    /// 「作成者が解禁しました。いつでも回せます」
    case forcedUnlocked
    /// 「全員OKで解禁 · あと N人」
    case waitingForAll(remaining: Int)
    /// 「過半数OKで解禁 · あと N人」
    case waitingForMajority(remaining: Int)
    /// 「締切 M/D(曜) HH:MM に解禁されます」
    case waitingForDeadline(deadlineAt: Date)

    /// ルームの状態からヒントを選ぶ。抽選の後（`drawn`・`closed`）と、締切の無い壊れた「締切日時」のルームは出さない（nil）。
    ///
    /// - `unlocked`: 強制解禁（`forcedUnlock`）なら「作成者が解禁しました」、それ以外は「条件を満たしました」
    ///   （引き直しが可決して戻った `unlocked` も、条件を満たしたものとして扱う）
    /// - `open`: 条件ごとの未解禁の文言。「あと N人」は `UnlockJudge.requiredReadyCount` から数え、0 より小さくしない
    ///   （自分の準備OKを楽観的に数えて条件に届いても、サーバーが `unlocked` にするまでの少しの間は「あと 0人」になる）
    /// - Parameter input: ルームの状態・条件・人数（画面に出している数。自分の楽観的な準備OKを含む）・締切・強制解禁したか
    static func make(_ input: UnlockInput) -> Self? {
        switch input.status {
        case .unlocked:
            return input.forcedUnlock ? .forcedUnlocked : .unlocked
        case .drawn, .closed:
            return nil
        case .open:
            break
        }
        let ready = max(input.readyCount, 0)
        switch input.rule {
        case .all:
            let required = UnlockJudge.requiredReadyCount(rule: .all, memberCount: input.memberCount) ?? 0
            return .waitingForAll(remaining: max(required - ready, 0))
        case .majority:
            let required = UnlockJudge.requiredReadyCount(rule: .majority, memberCount: input.memberCount) ?? 0
            return .waitingForMajority(remaining: max(required - ready, 0))
        case .deadline:
            return input.deadlineAt.map { .waitingForDeadline(deadlineAt: $0) }
        }
    }

    /// 締切の日時を「11/8(土) 21:00」の形にする（02 の §5.2 の `M/D(曜) HH:MM`。月と日は 0 で埋めず、時と分は 2 桁）。
    ///
    /// 並びは資料で決まっているので、`DGDateText` と同じく暦の値から組み立てる（和暦などの暦の設定によらず、グレゴリオ暦で読む）。
    /// 曜日の文字だけは言語の書き方に合わせる（`Date.FormatStyle` の短い曜日。日本語なら「土」）
    /// - Parameters:
    ///   - date: 締切日時
    ///   - timeZone: 暦を読むタイムゾーン（画面では端末のタイムゾーン）
    ///   - locale: 曜日を書く言語（画面では端末の言語）
    static func deadlineText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let weekday = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).weekday(.abbreviated))
        let hour = twoDigits(parts.hour ?? 0)
        let minute = twoDigits(parts.minute ?? 0)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)(\(weekday)) \(hour):\(minute)"
    }

    /// 2 桁に 0 で埋める
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
