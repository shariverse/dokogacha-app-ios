//
//  MemberInviteAvailability.swift
//  Dokogacha
//
//  S-07 のアバターの並びの「＋」（招待）と S-11 の「招待する」を出すか・押せるか（02 の §2.4 F-04 の参加条件）。
//

import Foundation

/// ルームにメンバーを招待できるか。
///
/// 招待しても参加できないルームには招待させない。参加の条件（02 の §2.4「ルームが open または unlocked、かつメンバーが20人未満」）を、
/// サーバー（`joinRoom` の `assertJoinable`）と同じ「状態 → 人数」の順に確かめる:
/// 1. 行き先が決まった（`drawn`）・終了した（`closed`）ルームは招待の入口を出さない（招待するものが無い）
/// 2. 満員（20 人）なら、入口は出したまま押せなくし、「満員」と理由を出す（誰かが抜けるとまた招待できるので、場所は残す）
///
/// 招待できるのは作成者に限らない（02 の §2.4 に作成者だけとは無く、S-11 の「招待する」もメンバー全員に出す）
nonisolated enum MemberInviteAvailability: Equatable, Sendable {
    /// 招待できる
    case available
    /// 満員（押せない）
    case full
    /// 招待できない状態（`drawn`・`closed`。入口を出さない）
    case unavailable

    /// 招待できるルームの状態（02 の §2.4 の参加条件）
    static let invitableStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// 招待の入口を出すか
    var isShown: Bool {
        self != .unavailable
    }

    /// ルームの状態と人数から決める。
    /// - Parameters:
    ///   - status: ルームの状態
    ///   - memberCount: メンバーの人数
    ///   - maxMembers: 1 ルームに参加できる人数（既定は 20）
    static func of(status: RoomStatus, memberCount: Int, maxMembers: Int = DomainConstants.Limits.maxMembers) -> Self {
        guard invitableStatuses.contains(status) else {
            return .unavailable
        }
        return memberCount < maxMembers ? .available : .full
    }
}
