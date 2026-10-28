//
//  Member.swift
//  Dokogacha
//

import Foundation

/// ルームのメンバー（`rooms/{roomId}/members/{uid}`。05 の §3）。ドキュメントの ID がメンバーの uid。
///
/// アプリが直接書き込めるのは自分の `ready` と `lastSeenAt` だけ（05 の §4）。
nonisolated struct Member: Codable, Sendable, Equatable {
    /// 表示名（参加時点のコピー。プロフィールを変えると Functions が更新する）
    var displayName: String
    /// アバターの色（参加時点のコピー）
    var avatarColor: String
    /// 役割
    var role: MemberRole
    /// 準備OK（F-30）
    var ready: Bool
    /// 参加した日時
    var joinedAt: Date
    /// 最後にルームを見た日時（NEW バッジの判定に使う。参加したときは `joinedAt` と同じ値で作る）
    var lastSeenAt: Date
}

/// メンバーの役割。`rawValue` は Firestore の `role` の値。
nonisolated enum MemberRole: String, CaseIterable, Codable, Sendable {
    /// 作成者
    case owner
    /// メンバー
    case member
}
