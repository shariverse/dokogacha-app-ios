//
//  AvatarPalette.swift
//  Dokogacha
//

import Foundation

/// アバターの色の候補（`users.avatarColor`・`members.avatarColor` に保存する値）。
///
/// 保存する値は tokens.json の `color.avatar` の `#RRGGBB`（大文字）。色の見た目の正本は `DesignSystem` の
/// `Color.dgAvatars` で、ここは保存する文字列だけを持つ（`DesignTokensTests` で tokens.json と突き合わせる）。
/// TypeScript 側の `backend/functions/src/domain/avatarPalette.ts` の `AVATAR_COLORS` も同じ値。
nonisolated enum AvatarPalette {
    /// 保存する値の一覧（tokens.json の `color.avatar` と同じ順）
    static let colors = ["#B8321A", "#23775D", "#2F6FD0", "#A3367E", "#6B48C9", "#8A5A12", "#1F6E8C", "#5E5045"]

    /// 保存された値が一覧の何番目か（`Color.dgAvatar(at:)` に渡す）。一覧に無い値は nil。
    /// - Parameter avatarColor: `users.avatarColor` などの値（大文字・小文字は区別しない）
    /// - Returns: 一覧の中の位置
    static func index(of avatarColor: String) -> Int? {
        colors.firstIndex(of: avatarColor.uppercased())
    }

    /// ユーザーを作るときの色を選ぶ（06 の §4 の仮決め「ユーザー作成時にランダム。ルーム内の重複は許容」）。
    /// - Parameter randomIndex: `0..<上限` の整数を返す乱数（テストでは固定の値を返す関数を渡す）
    /// - Returns: 選んだ色の値
    static func random(randomIndex: (Int) -> Int) -> String {
        colors[randomIndex(colors.count)]
    }
}
