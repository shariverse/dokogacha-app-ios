//
//  RerollRule.swift
//  Dokogacha
//
//  引き直し（02 の §6.4・F-43）の過半数の判定。
//  TypeScript 側の `backend/functions/src/domain/reroll.ts` と同じ式で、同じケースを Swift Testing と Jest の両方で確かめる。
//  判定するのはサーバー（`voteReroll`・`proposeReroll`・`expireRerolls`・退出）と擬似のサーバーで、
//  画面は同じ式で「賛成を集めています…（N/M人）」の N を数える。
//

import Foundation

/// 引き直しの過半数の判定
nonisolated enum RerollRule {
    /// 賛成が過半数か（02 の §6.4「賛成が過半数（> メンバー数 ÷ 2）」）。
    ///
    /// 割り算の誤差を避けるため、`賛成 × 2 > メンバー数` の整数で比べる。メンバーが 0 人なら可決しない
    /// - Parameters:
    ///   - approvals: 賛成の数（`approvalCount(votesFor:memberIds:)` で数えたもの）
    ///   - memberCount: メンバーの数（作成者を含む）
    static func isMajority(approvals: Int, memberCount: Int) -> Bool {
        memberCount > 0 && approvals * 2 > memberCount
    }

    /// 賛成の数。今のメンバーの票だけを、1 人 1 票で数える（同じ uid が重なっていても 1 票。退出した人の票は数えない）
    /// - Parameters:
    ///   - votesFor: 賛成した人の uid（`reroll.votesFor`）
    ///   - memberIds: 今のメンバーの uid（`memberIds`）
    static func approvalCount(votesFor: [String], memberIds: [String]) -> Int {
        Set(votesFor).intersection(memberIds).count
    }
}
