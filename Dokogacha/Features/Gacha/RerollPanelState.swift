//
//  RerollPanelState.swift
//  Dokogacha
//

import Foundation

/// S-14 の引き直し（F-43）の欄に出すもの（03 の S-14 の 5・02 の §6.4 の表示）。
///
/// ルームの購読の値と、出している抽選の ID・自分の uid から `make(room:drawID:userID:)` で決める値の型にして、Unit テストで確かめる。
nonisolated enum RerollPanelState: Equatable, Sendable {
    /// 出さない（`closed` の閲覧のみ・ルームを読めていない・行き先が決まる前の壊れた状態）
    case hidden
    /// 点線のボタン「引き直しを提案（過半数の賛成で1回まで）」を押せる
    case proposable
    /// 投票中。「賛成を集めています…（N/M人）」と賛成／反対のボタン
    case voting(approvals: Int, memberCount: Int, myVote: RerollVote?)
    /// 可決して、もう一度引ける（「過半数が賛成。もう一度引けます」と S-13 に進むボタン）
    case passed
    /// 可決の後に、ほかの人がもう回し直した（出している抽選が前のもの）。「新しい行き先が決まりました」と、S-13 で新しい抽選を見るボタン
    case redrawn
    /// 引き直しの権利を使った後（否決・可決の後にもう一度回した結果）。「引き直しは使用済みです」（押せない）
    case used

    /// 引き直しの欄に出すもの。
    ///
    /// - `closed` は閲覧のみで出さない（03 の S-14「閲覧のみのときは 5・6 を表示しない」）
    /// - 投票中（`drawn` で `voting`）は、今のメンバーの賛成の数（`RerollRule.approvalCount`）とメンバーの数（`memberIds`）、自分の票
    /// - 可決（`passed`）で、まだ回し直していない（`unlocked`）なら「もう一度引けます」
    /// - 可決の後の `drawn` で、出している抽選が前のもの（ほかの人が回し直した）なら「新しい行き先が決まりました」（もう回さず、新しい結果を見る）
    /// - 提案前（`none` で権利を使っていない）の `drawn` で、出している抽選が今の抽選なら提案できる
    /// - それ以外の `drawn`（否決・可決の後にもう一度回した結果）は使用済み。`open`・`unlocked` で可決でなければ出さない
    /// - Parameters:
    ///   - room: ルーム（まだ読めていなければ nil）
    ///   - drawID: S-14 に出している抽選の ID
    ///   - userID: 自分の uid
    static func make(room: Room?, drawID: String, userID: String) -> Self {
        guard let room, room.status != .closed else {
            return .hidden
        }
        let reroll = room.reroll
        switch (room.status, reroll.status) {
        case (.drawn, .voting):
            let myVote: RerollVote? = if reroll.votesFor.contains(userID) {
                .approve
            } else if reroll.votesAgainst.contains(userID) {
                .reject
            } else {
                nil
            }
            return .voting(
                approvals: RerollRule.approvalCount(votesFor: reroll.votesFor, memberIds: room.memberIds),
                memberCount: room.memberIds.count,
                myVote: myVote
            )
        case (.unlocked, .passed):
            return .passed
        case (.drawn, .passed) where room.currentDrawId != drawID:
            return .redrawn
        case (.drawn, .notProposed) where !reroll.used && room.currentDrawId == drawID:
            return .proposable
        case (.drawn, _):
            return .used
        default:
            return .hidden
        }
    }
}

/// 自分の引き直しの票
nonisolated enum RerollVote: Equatable, Sendable {
    /// 賛成
    case approve
    /// 反対
    case reject
}
