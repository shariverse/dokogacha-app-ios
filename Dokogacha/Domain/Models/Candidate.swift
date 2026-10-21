//
//  Candidate.swift
//  Dokogacha
//

import Foundation

/// 候補（`rooms/{roomId}/candidates/{candidateId}`。05 の §3）。
///
/// 作成・削除は Callable Functions（`addCandidate`・`deleteCandidate`）。アプリが直接書けるのは
/// `likedBy` に自分の uid を足す・外すことだけ（05 の §4）。
nonisolated struct Candidate: Codable, Sendable, Equatable {
    /// 場所
    var place: Place
    /// カテゴリ
    var category: PlaceCategory
    /// ひとこと（0〜40 文字）
    var note: String
    /// 参考 URL（無ければ nil）
    var url: String?
    /// 投稿した人の uid
    var postedBy: String
    /// 投稿した人の表示名（投稿時点のコピー）
    var postedByName: String
    /// 投稿順の通し番号（カプセルの色に使う）
    var colorIndex: Int
    /// いいねしたメンバーの uid
    var likedBy: [String]
    /// 過去のアイデアから持ち込んだときの元（`pastIdeas/{ideaId}`）。持ち込みでなければ nil
    var fromPastIdeaId: String?
    /// 投稿日時（並び順に使う）
    var createdAt: Date
}
