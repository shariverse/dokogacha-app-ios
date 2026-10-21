//
//  CandidateList.swift
//  Dokogacha
//
//  ルーム画面（S-07）の候補一覧の並び順と NEW バッジ（02 の §3.3・F-12）の判定。
//

import Foundation

/// 候補一覧の並び順と NEW の判定。
nonisolated enum CandidateList {
    /// 新しい順（投稿日時の降順）に並べる（F-12「最新の投稿が一番上」）。
    ///
    /// 投稿日時が同じ候補は、端末や購読の順で入れ替わらないよう ID の昇順で並べる。
    /// - Parameter candidates: 候補
    /// - Returns: 新しい順の候補
    static func sorted(_ candidates: [Identified<Candidate>]) -> [Identified<Candidate>] {
        candidates.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    /// NEW バッジを付けるか（F-12「前回このルームを開いた時刻（`lastSeenAt`）より後に投稿された、他人の候補」）。
    ///
    /// `lastSeenAt` と同じ時刻の投稿は NEW にしない（より後だけ）。`lastSeenAt` は参加したときに `joinedAt` と同じ値で作るので、
    /// 参加より前からある候補は NEW にならない。
    /// - Parameters:
    ///   - candidate: 候補
    ///   - myUID: 自分の uid
    ///   - lastSeenAt: 自分のメンバーの `lastSeenAt`（ルーム画面を開いた時点の値）
    static func isNew(_ candidate: Candidate, myUID: String, lastSeenAt: Date) -> Bool {
        candidate.postedBy != myUID && candidate.createdAt > lastSeenAt
    }

    /// NEW の候補の数（F-12「前回見たあとに N件の候補が増えました」の N）。
    /// - Parameters:
    ///   - candidates: 候補
    ///   - myUID: 自分の uid
    ///   - lastSeenAt: 自分のメンバーの `lastSeenAt`（ルーム画面を開いた時点の値）
    static func newCount(_ candidates: [Candidate], myUID: String, lastSeenAt: Date) -> Int {
        candidates.count(where: { isNew($0, myUID: myUID, lastSeenAt: lastSeenAt) })
    }
}
