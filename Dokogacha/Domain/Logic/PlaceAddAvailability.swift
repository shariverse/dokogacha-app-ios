//
//  PlaceAddAvailability.swift
//  Dokogacha
//
//  S-08 の検索結果の行の「追加」「追加済み」「上限」（03 の S-08 の 3）と、02 の F-10 の上限・重複・状態の判定。
//

import Foundation

/// 検索結果の場所を、いまのルームに追加できるか。
///
/// サーバー（`addCandidate`）は「状態 → 重複 → 上限」の順に確かめる。画面では、押す前に分かることを先に出す:
/// - 自分がすでに投稿した場所は「追加済み」（押せない。自分の投稿にはいいねもできないので、誘導する先が無い）
/// - 投稿数が上限に達していたら「上限」（押せない。02 の F-10「ボタンを「上限」表示にして無効化」）
/// - ほかの人がすでに投稿した場所は「追加」のまま押せ、押すと S-09 を開かずに「すでに候補にあります。いいねしますか？」を出す
///   （02 の F-10 の重複の確認。入力を書かせてから断らないため）
/// - 投稿を受け付けない状態（`drawn`・`closed`）・ルームがまだ届いていないときは押せない
nonisolated enum PlaceAddAvailability: Equatable, Sendable {
    /// 追加できる（「追加」→ S-09）
    case addable
    /// ほかの人が同じ場所を投稿している（「追加」→ 重複の確認。値は既存の候補の ID）
    case duplicate(candidateID: String)
    /// 自分が同じ場所を投稿している（「追加済み」。押せない）
    case added
    /// 自分の投稿数が上限に達している（「上限」。押せない）
    case limitReached
    /// ルームが投稿を受け付けない・まだ届いていない（「追加」のまま押せない）
    case unavailable

    /// 行のボタンを押せるか
    var isEnabled: Bool {
        switch self {
        case .addable, .duplicate:
            true
        case .added, .limitReached, .unavailable:
            false
        }
    }

    /// 場所の追加の可否を決める。
    /// - Parameters:
    ///   - place: 検索結果の場所
    ///   - candidates: ルームの候補
    ///   - userID: 自分の uid
    ///   - postLimit: 1 人あたりの投稿数（ルームの設定）
    ///   - acceptsCandidates: ルームが投稿を受け付ける状態か（F-10「投稿できるのは open/unlocked のときだけ」）
    static func of(
        _ place: Place,
        candidates: [Identified<Candidate>],
        userID: String,
        postLimit: Int,
        acceptsCandidates: Bool
    ) -> Self {
        guard acceptsCandidates else {
            return .unavailable
        }
        let duplicateID = CandidateRules.duplicate(of: place, in: candidates)
        let postedByMe = candidates.contains { candidate in
            candidate.postedBy == userID && CandidateRules.isSamePlace(place, candidate.place)
        }
        if postedByMe {
            return .added
        }
        if myPostCount(in: candidates, userID: userID) >= postLimit {
            return .limitReached
        }
        if let duplicateID {
            return .duplicate(candidateID: duplicateID)
        }
        return .addable
    }

    /// 自分の投稿の数（「あなたの投稿 n/上限」の n）
    static func myPostCount(in candidates: [Identified<Candidate>], userID: String) -> Int {
        candidates.count { $0.postedBy == userID }
    }
}
