//
//  RerollRuleTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 引き直しの過半数の判定（F-43）を確かめる。
///
/// TypeScript 側の `backend/functions/src/domain/reroll.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct RerollRuleTests {
    /// 過半数のケース 1 件（賛成の数・メンバーの数・可決するか）
    nonisolated struct MajorityCase: Sendable, CustomTestStringConvertible {
        let approvals: Int
        let members: Int
        let expected: Bool

        var testDescription: String {
            "賛成 \(approvals) / メンバー \(members) 人 → \(expected)"
        }
    }

    nonisolated static let majorityCases: [MajorityCase] = [
        MajorityCase(approvals: 1, members: 1, expected: true),
        MajorityCase(approvals: 1, members: 2, expected: false),
        MajorityCase(approvals: 2, members: 2, expected: true),
        MajorityCase(approvals: 1, members: 3, expected: false),
        MajorityCase(approvals: 2, members: 3, expected: true),
        MajorityCase(approvals: 2, members: 4, expected: false),
        MajorityCase(approvals: 3, members: 4, expected: true),
        MajorityCase(approvals: 2, members: 5, expected: false),
        MajorityCase(approvals: 3, members: 5, expected: true),
        MajorityCase(approvals: 10, members: 20, expected: false),
        MajorityCase(approvals: 11, members: 20, expected: true),
        MajorityCase(approvals: 0, members: 3, expected: false),
        MajorityCase(approvals: 0, members: 0, expected: false)
    ]

    /// 02 の §6.4「賛成が過半数（> メンバー数 ÷ 2）」。ちょうど半分では可決しない
    @Test(arguments: majorityCases)
    func majority(_ testCase: MajorityCase) {
        #expect(RerollRule.isMajority(approvals: testCase.approvals, memberCount: testCase.members) == testCase.expected)
    }

    /// 今のメンバーの票だけを 1 人 1 票で数える
    @Test
    func countsCurrentMembersOnce() {
        #expect(RerollRule.approvalCount(votesFor: ["a", "b"], memberIds: ["a", "b", "c"]) == 2)
        #expect(RerollRule.approvalCount(votesFor: ["a", "a", "b"], memberIds: ["a", "b", "c"]) == 2)
        #expect(RerollRule.approvalCount(votesFor: ["a", "left"], memberIds: ["a", "b"]) == 1)
        #expect(RerollRule.approvalCount(votesFor: [], memberIds: ["a"]) == 0)
    }
}
