//
//  UnlockJudgeTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 解禁の判定（F-31）と強制解禁（F-32）を確かめる（06 の §2 の「解禁（F-31）」）。
///
/// TypeScript 側の `backend/functions/src/domain/unlock.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct UnlockJudgeTests {
    /// 判定の時刻の基準（2026-10-27 12:00:00 JST）
    nonisolated static let now = Date(timeIntervalSince1970: 1_793_070_000)

    /// 入力を作る（指定しない値は「`open`・強制解禁なし・締切なし」）
    static func input(
        _ rule: UnlockRule,
        members: Int,
        ready: Int,
        status: RoomStatus = .open,
        deadlineAt: Date? = nil,
        forced: Bool = false
    ) -> UnlockInput {
        UnlockInput(
            status: status, rule: rule, memberCount: members, readyCount: ready, deadlineAt: deadlineAt, forcedUnlock: forced
        )
    }

    // MARK: 全員OK・過半数OK

    /// 人数の条件のケース 1 件（条件・メンバーの数・準備OKの数・結果）
    nonisolated struct CountCase: Sendable, CustomTestStringConvertible {
        let rule: UnlockRule
        let members: Int
        let ready: Int
        let expected: UnlockJudgement

        var testDescription: String {
            "\(rule) \(ready)/\(members)"
        }
    }

    /// 人数の条件のケース。
    /// 06 の §2: 全員OK 4/5→未・5/5→解禁、過半数 2/4→未・3/4→解禁・3/5→解禁。加えて過半数の 1 人・20 人
    nonisolated static let countCases: [CountCase] = [
        CountCase(rule: .all, members: 5, ready: 4, expected: .waitingForAll(remaining: 1)),
        CountCase(rule: .all, members: 5, ready: 5, expected: .unlocked(.allReady)),
        CountCase(rule: .all, members: 5, ready: 0, expected: .waitingForAll(remaining: 5)),
        CountCase(rule: .all, members: 1, ready: 0, expected: .waitingForAll(remaining: 1)),
        CountCase(rule: .all, members: 1, ready: 1, expected: .unlocked(.allReady)),
        CountCase(rule: .majority, members: 4, ready: 2, expected: .waitingForMajority(remaining: 1)),
        CountCase(rule: .majority, members: 4, ready: 3, expected: .unlocked(.majorityReady)),
        CountCase(rule: .majority, members: 5, ready: 2, expected: .waitingForMajority(remaining: 1)),
        CountCase(rule: .majority, members: 5, ready: 3, expected: .unlocked(.majorityReady)),
        CountCase(rule: .majority, members: 1, ready: 0, expected: .waitingForMajority(remaining: 1)),
        CountCase(rule: .majority, members: 1, ready: 1, expected: .unlocked(.majorityReady)),
        CountCase(rule: .majority, members: 20, ready: 0, expected: .waitingForMajority(remaining: 11)),
        CountCase(rule: .majority, members: 20, ready: 10, expected: .waitingForMajority(remaining: 1)),
        CountCase(rule: .majority, members: 20, ready: 11, expected: .unlocked(.majorityReady))
    ]

    /// 全員OKは `OK人数 = メンバー数`、過半数OKは `OK人数 > メンバー数 ÷ 2`。未解禁なら「あと N人」の N を返す
    @Test(arguments: Self.countCases)
    func countRules(testCase: CountCase) {
        let input = Self.input(testCase.rule, members: testCase.members, ready: testCase.ready)
        #expect(UnlockJudge.judge(input, now: Self.now) == testCase.expected)
        #expect(UnlockJudge.nextStatus(input, now: Self.now) == (testCase.expected.isUnlocked ? .unlocked : .open))
    }

    /// 解禁に要る人数（全員OK はメンバーの数、過半数OK は `メンバー数 ÷ 2 を切り捨てて + 1`。0 人なら 1。締切日時は nil）
    @Test
    func requiredReadyCount() {
        #expect(UnlockJudge.requiredReadyCount(rule: .all, memberCount: 5) == 5)
        #expect(UnlockJudge.requiredReadyCount(rule: .all, memberCount: 0) == 1)
        #expect(UnlockJudge.requiredReadyCount(rule: .majority, memberCount: 4) == 3)
        #expect(UnlockJudge.requiredReadyCount(rule: .majority, memberCount: 5) == 3)
        #expect(UnlockJudge.requiredReadyCount(rule: .majority, memberCount: 1) == 1)
        #expect(UnlockJudge.requiredReadyCount(rule: .majority, memberCount: 20) == 11)
        #expect(UnlockJudge.requiredReadyCount(rule: .majority, memberCount: 0) == 1)
        #expect(UnlockJudge.requiredReadyCount(rule: .deadline, memberCount: 5) == nil)
    }

    /// 人数の条件では締切日時を見ない（過ぎた締切が残っていても解禁しない）
    @Test
    func countRulesIgnoreDeadline() {
        let past = Self.now.addingTimeInterval(-60)
        #expect(UnlockJudge.judge(Self.input(.all, members: 3, ready: 0, deadlineAt: past), now: Self.now) == .waitingForAll(remaining: 3))
        #expect(
            UnlockJudge.judge(Self.input(.majority, members: 3, ready: 1, deadlineAt: past), now: Self.now)
                == .waitingForMajority(remaining: 1)
        )
    }

    // MARK: 締切日時

    /// 06 の §2「締切：前後1秒」。締切の 1 秒前は未解禁、ちょうどと 1 秒後は解禁（`今 ≥ 締切日時`）
    @Test(arguments: [(-1.0, false), (0.0, true), (1.0, true)])
    func deadlineBoundary(offset: TimeInterval, unlocked: Bool) {
        let deadline = Self.now
        let input = Self.input(.deadline, members: 5, ready: 0, deadlineAt: deadline)
        let expected: UnlockJudgement = unlocked ? .unlocked(.deadlinePassed) : .waitingForDeadline(deadlineAt: deadline)
        #expect(UnlockJudge.judge(input, now: deadline.addingTimeInterval(offset)) == expected)
        #expect(UnlockJudge.nextStatus(input, now: deadline.addingTimeInterval(offset)) == (unlocked ? .unlocked : .open))
    }

    /// 締切日時の条件では準備OKは参考表示のみ（全員がOKでも締切の前は解禁しない）
    @Test
    func deadlineIgnoresReady() {
        let deadline = Self.now.addingTimeInterval(1)
        let input = Self.input(.deadline, members: 5, ready: 5, deadlineAt: deadline)
        #expect(UnlockJudge.judge(input, now: Self.now) == .waitingForDeadline(deadlineAt: deadline))
    }

    /// 締切日時が無い壊れたデータは解禁しない（締切の日時は nil で返す）
    @Test
    func deadlineMissing() {
        let input = Self.input(.deadline, members: 5, ready: 5)
        #expect(UnlockJudge.judge(input, now: Self.now) == .waitingForDeadline(deadlineAt: nil))
        #expect(UnlockJudge.nextStatus(input, now: Self.now) == .open)
    }

    // MARK: 強制解禁（F-32）

    /// 06 の §2「強制解禁はOK数に関係なく解禁」。どの条件でも、準備OKが 0 人でも、締切の前でも解禁
    @Test(arguments: UnlockRule.allCases)
    func forcedUnlockIgnoresConditions(rule: UnlockRule) {
        let input = Self.input(rule, members: 5, ready: 0, deadlineAt: Self.now.addingTimeInterval(60), forced: true)
        #expect(UnlockJudge.judge(input, now: Self.now) == .unlocked(.forced))
        #expect(UnlockJudge.nextStatus(input, now: Self.now) == .unlocked)
    }

    /// 強制解禁して条件も満たしているときは、理由を「強制解禁」にする（取り消しで文言が変わらない）
    @Test
    func forcedUnlockWinsOverConditions() {
        let input = Self.input(.all, members: 3, ready: 3, forced: true)
        #expect(UnlockJudge.judge(input, now: Self.now) == .unlocked(.forced))
    }

    // MARK: 数え直し前の値

    /// 準備OKの数がメンバーの数を超えた入力（退出の直後の数え直し前の値）は、メンバーの数に収めて判定する
    @Test
    func readyCountAboveMembersIsClamped() {
        #expect(UnlockJudge.judge(Self.input(.all, members: 5, ready: 6), now: Self.now) == .unlocked(.allReady))
        #expect(UnlockJudge.judge(Self.input(.majority, members: 5, ready: 7), now: Self.now) == .unlocked(.majorityReady))
    }

    /// 負の数は 0 とみなす。メンバーが 0 人のルームは解禁しない
    @Test
    func negativeAndZeroCounts() {
        #expect(UnlockJudge.judge(Self.input(.all, members: 5, ready: -1), now: Self.now) == .waitingForAll(remaining: 5))
        #expect(UnlockJudge.judge(Self.input(.all, members: 0, ready: 0), now: Self.now) == .waitingForAll(remaining: 1))
        #expect(UnlockJudge.judge(Self.input(.majority, members: 0, ready: 0), now: Self.now) == .waitingForMajority(remaining: 1))
        #expect(UnlockJudge.judge(Self.input(.all, members: -1, ready: 2), now: Self.now) == .waitingForAll(remaining: 1))
    }

    // MARK: ルームの状態

    /// `unlocked` のルームも同じ式で判定し直す。誰かが取り消して条件を満たさなくなれば `open` に戻る（02 の §2.1）
    @Test
    func unlockedRoomFallsBackToOpen() {
        let input = Self.input(.all, members: 5, ready: 4, status: .unlocked)
        #expect(UnlockJudge.judge(input, now: Self.now) == .waitingForAll(remaining: 1))
        #expect(UnlockJudge.nextStatus(input, now: Self.now) == .open)
    }

    /// 強制解禁したルームは、取り消しがあっても `unlocked` のまま（F-30〜32 の AC）
    @Test
    func forcedRoomStaysUnlocked() {
        let input = Self.input(.all, members: 5, ready: 0, status: .unlocked, forced: true)
        #expect(UnlockJudge.nextStatus(input, now: Self.now) == .unlocked)
    }

    /// `drawn`・`closed` は判定せず、状態を変えない（準備OKが揃っていても・強制解禁でも・締切を過ぎていても）
    @Test(arguments: [RoomStatus.drawn, .closed])
    func drawnOrClosedIsNotJudged(status: RoomStatus) {
        let past = Self.now.addingTimeInterval(-1)
        for input in [
            Self.input(.all, members: 3, ready: 3, status: status),
            Self.input(.majority, members: 3, ready: 0, status: status, forced: true),
            Self.input(.deadline, members: 3, ready: 0, status: status, deadlineAt: past)
        ] {
            #expect(UnlockJudge.judge(input, now: Self.now) == .notApplicable)
            #expect(UnlockJudge.nextStatus(input, now: Self.now) == status)
        }
    }

    /// `isUnlocked` は解禁のときだけ true
    @Test
    func isUnlocked() {
        #expect(UnlockJudgement.unlocked(.allReady).isUnlocked)
        #expect(!UnlockJudgement.waitingForAll(remaining: 1).isUnlocked)
        #expect(!UnlockJudgement.waitingForDeadline(deadlineAt: nil).isUnlocked)
        #expect(!UnlockJudgement.notApplicable.isUnlocked)
    }
}
