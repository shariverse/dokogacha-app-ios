//
//  PastIdea.swift
//  Dokogacha
//

import Foundation

/// 過去のアイデア（`users/{uid}/pastIdeas/{ideaId}`。05 の §3・F-13）。
///
/// ルームが終了したときに Functions が、当選しなかった候補をメンバーごとに作る。
nonisolated struct PastIdea: Codable, Sendable, Equatable {
    /// 元のルームの ID
    var sourceRoomId: String
    /// 元のルームの名前（グループの見出しに出す）
    var sourceRoomName: String
    /// 元のルームが終了した日時（並び替えに使う）
    var sourceClosedAt: Date
    /// 元のルームで当選した場所の名前（「◯◯ ゆき」に出す）
    var sourceWinnerName: String
    /// 場所（候補の `place` と同じ）
    var place: Place
    /// カテゴリ
    var category: PlaceCategory
    /// 前回のいいね数（「前回 N いいね」・「前回惜しかった」に使う）
    var prevLikeCount: Int
}
