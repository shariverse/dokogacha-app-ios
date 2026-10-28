//
//  UnlockJudge.swift
//  Dokogacha
//
//  解禁の判定（02 の §5.2・F-31）と強制解禁（F-32）。
//  TypeScript 側の `backend/functions/src/domain/unlock.ts` と同じ判定で、06 の §2 の同じケースを両方で確かめる。
//  ルームの `status` を書き換えるのはサーバー（`onMemberWrite`・`forceUnlock`・`checkDeadlines`）で、
//  アプリはこの判定をヒントの文言（「あと N人」など）にだけ使う。
//
//  締切日時は分単位（作成画面・設定画面の日時ピッカーで分まで選ぶ）。判定は `Date` どうしで比べるので、
//  秒の端数がある値でもそのまま比べる。締切での解禁はサーバーの `checkDeadlines` が 5 分ごと（06 の §4 の仮決め）に
//  まとめて判定するので、`status` が `unlocked` になるのは締切から最大 5 分後になる。
//

import Foundation

/// 解禁の判定の入力（ルーム 1 つ分）。
///
/// 準備OKの数は `rooms.readyCount` のフィールドではなく、呼び出し側が数え直した値を渡す
/// （`onMemberWrite` はメンバーの書き込みのたびに数え直す。フィールドは書き込みの順で古い値のことがある）。
nonisolated struct UnlockInput: Equatable, Sendable {
    /// ルームの今の状態
    let status: RoomStatus
    /// 解禁の条件（`settings.unlockRule`）
    let rule: UnlockRule
    /// メンバーの数（作成者を含む）
    let memberCount: Int
    /// 準備OKにしているメンバーの数（作成者を含む）
    let readyCount: Int
    /// 締切日時（`settings.deadlineAt`。条件が「締切日時」のときだけ見る）
    let deadlineAt: Date?
    /// 作成者が強制解禁したか（`rooms.forcedUnlock`）
    let forcedUnlock: Bool
}

/// 解禁した理由（ヒントの文言と Analytics の `room_unlock` の `forced` を選ぶため）。
nonisolated enum UnlockReason: CaseIterable, Sendable {
    /// 全員が準備OK（条件「全員OK」）
    case allReady
    /// 過半数が準備OK（条件「過半数OK」）
    case majorityReady
    /// 締切日時を過ぎた（条件「締切日時」）
    case deadlinePassed
    /// 作成者が強制解禁した（F-32。条件によらない）
    case forced
}

/// 解禁の判定の結果。
nonisolated enum UnlockJudgement: Equatable, Sendable {
    /// 解禁している。S-07 の「条件を満たしました。誰が回してもOK！」／「作成者が解禁しました。いつでも回せます」
    case unlocked(UnlockReason)
    /// 全員OKを待っている。S-07 の「全員OKで解禁 · あと N人」の N
    case waitingForAll(remaining: Int)
    /// 過半数OKを待っている。S-07 の「過半数OKで解禁 · あと N人」の N
    case waitingForMajority(remaining: Int)
    /// 締切日時を待っている。S-07 の「締切 M/D(曜) HH:MM に解禁されます」の日時（締切の無い壊れたデータでは nil）
    case waitingForDeadline(deadlineAt: Date?)
    /// 抽選の後（`drawn`・`closed`）。解禁の判定をしない（状態を変えない）
    case notApplicable

    /// 解禁しているか
    var isUnlocked: Bool {
        if case .unlocked = self {
            return true
        }
        return false
    }
}

/// 解禁の判定（F-31・F-32）。
///
/// どれも副作用の無い純粋な関数で、時刻は `now` で渡す（テストで締切の前後 1 秒を確かめるため）。
/// 判定は「今の値だけ」で決まり、前の状態に頼らない。そのため、解禁した後に誰かが準備OKを取り消すと
/// 条件を満たさなくなって `open` に戻り（02 の §2.1）、強制解禁は `forcedUnlock` が残る限り解禁のまま（F-30〜32 の AC）。
nonisolated enum UnlockJudge {
    /// 解禁しているかと、未解禁ならあと何が要るかを判定する。
    ///
    /// - `drawn`・`closed` は判定しない（`notApplicable`）。`open`・`unlocked` は同じ式で判定し直す
    /// - 強制解禁（`forcedUnlock`）は条件によらず解禁。条件も満たしているときも理由は「強制解禁」にする
    ///   （取り消しで条件を満たさなくなっても文言が変わらないように）
    /// - 全員OK: `OK人数 = メンバー数`。過半数OK: `OK人数 > メンバー数 ÷ 2`（整数で `OK人数 × 2 > メンバー数`）
    /// - 締切日時: `今 ≥ 締切日時`（ちょうどで解禁）。準備OKの数は見ない（02 の §5.2「参考表示のみ」）
    ///
    /// 数が壊れていても判定できるように、メンバーの数は 0 以上、準備OKの数は 0〜メンバーの数に収めてから比べる。
    /// メンバーが 0 人のルームは、どの条件でも準備OKが 1 人以上要るので解禁しない。
    /// 締切日時は分単位で、`今 ≥ 締切日時` を `Date` で比べる（ファイルの先頭の説明）。
    /// - Parameters:
    ///   - input: ルームの状態・条件・人数・締切
    ///   - now: 今の時刻（サーバーでは `Timestamp.now()`）
    static func judge(_ input: UnlockInput, now: Date) -> UnlockJudgement {
        guard input.status == .open || input.status == .unlocked else {
            return .notApplicable
        }
        if input.forcedUnlock {
            return .unlocked(.forced)
        }
        let memberCount = max(input.memberCount, 0)
        let readyCount = min(max(input.readyCount, 0), memberCount)
        switch input.rule {
        case .all:
            let remaining = allRequired(memberCount: memberCount) - readyCount
            return remaining <= 0 ? .unlocked(.allReady) : .waitingForAll(remaining: remaining)
        case .majority:
            let remaining = majorityRequired(memberCount: memberCount) - readyCount
            return remaining <= 0 ? .unlocked(.majorityReady) : .waitingForMajority(remaining: remaining)
        case .deadline:
            guard let deadlineAt = input.deadlineAt else {
                return .waitingForDeadline(deadlineAt: nil)
            }
            return now >= deadlineAt ? .unlocked(.deadlinePassed) : .waitingForDeadline(deadlineAt: deadlineAt)
        }
    }

    /// 判定の後のルームの状態（`onMemberWrite`・`checkDeadlines` が `status` に書く値）。
    ///
    /// `open`・`unlocked` は解禁していれば `unlocked`、していなければ `open`。`drawn`・`closed` はそのまま。
    /// - Parameters:
    ///   - input: ルームの状態・条件・人数・締切
    ///   - now: 今の時刻
    static func nextStatus(_ input: UnlockInput, now: Date) -> RoomStatus {
        switch judge(input, now: now) {
        case .notApplicable: input.status
        case .unlocked: .unlocked
        case .waitingForAll, .waitingForMajority, .waitingForDeadline: .open
        }
    }

    /// 解禁に要る準備OKの人数（「全員OK」「過半数OK」のとき）。
    ///
    /// 全員OKはメンバーの数（0 人なら 1）、過半数OKは `メンバー数 ÷ 2 を切り捨てて + 1`
    /// （偶数の 4 人なら 3・奇数の 5 人なら 3・1 人なら 1・20 人なら 11）。締切日時は人数で決まらないので nil。
    /// - Parameters:
    ///   - rule: 解禁の条件
    ///   - memberCount: メンバーの数（作成者を含む）
    static func requiredReadyCount(rule: UnlockRule, memberCount: Int) -> Int? {
        switch rule {
        case .all: allRequired(memberCount: memberCount)
        case .majority: majorityRequired(memberCount: memberCount)
        case .deadline: nil
        }
    }

    /// 全員OKに要る人数（メンバーの数。0 人なら 1）
    private static func allRequired(memberCount: Int) -> Int {
        max(memberCount, 1)
    }

    /// 過半数OKに要る人数（`OK人数 > メンバー数 ÷ 2` を満たす最小の整数）
    private static func majorityRequired(memberCount: Int) -> Int {
        max(memberCount, 0) / 2 + 1
    }
}
