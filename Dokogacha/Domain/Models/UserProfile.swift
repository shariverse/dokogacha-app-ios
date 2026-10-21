//
//  UserProfile.swift
//  Dokogacha
//

import Foundation

/// ユーザーのプロフィール（`users/{uid}`。05 の §3）。
///
/// プロパティ名は Firestore のフィールド名と同じ（`Codable` の鍵になる）。日時は `Date` で持ち、
/// Firestore の `Timestamp` との変換はデータ層（`Data/`）で行う。
nonisolated struct UserProfile: Codable, Sendable, Equatable {
    /// 表示名（1〜10 文字。`DomainConstants.Limits.displayNameLength`）
    var displayName: String
    /// アバターの色（`avatar` パレットの `#RRGGBB`。`AvatarPalette`）
    var avatarColor: String
    /// 広告非表示を購入済みか（Functions の `verifyPurchase` だけが書き込む）
    var adFree: Bool
    /// 通知のトークン（FCM）
    var fcmTokens: [String]
    /// 作成日時
    var createdAt: Date
}
