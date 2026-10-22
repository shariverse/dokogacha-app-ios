//
//  GachaDraw.swift
//  Dokogacha
//
//  抽選（02 の §6.1・F-40）の重み付きの選択。TypeScript 側の `backend/functions/src/domain/draw.ts` と同じ式で、
//  06 の §2 の抽選のケースを両方で確かめる。本物の抽選はサーバーの `drawGacha` だけが行い（クライアントで乱数を引かない）、
//  アプリではメモリ上の擬似のサーバー（プレビュー・Unit テスト・`-uiTesting`）がこの関数で抽選する。
//

import Foundation

/// 抽選の対象の候補 1 件（ID と重み）。
nonisolated struct DrawEntry: Equatable, Sendable {
    /// 候補の ID
    let id: String
    /// 重み（F-21）
    let weight: Double
}

/// 抽選の結果（抽選の記録 `draws/{drawId}` に書く値）。
nonisolated struct DrawOutcome: Equatable, Sendable {
    /// 当選した候補の ID
    let candidateID: String
    /// 当選時の確率（0〜1。`Probability.odds(of:)` の確率と同じ値）
    let probability: Double
    /// 抽選時の重みのスナップショット（抽選の対象の候補の ID → 重み。除外した候補は入らない）
    let weights: [String: Double]
}

/// 抽選の重み付きの選択。
///
/// 抽選の対象の候補を ID 順に並べ（`Probability.eligibleInIDOrder`）、重みの累積の区間 `[累積の前, 累積)` に
/// `u × 重みの合計`（`u = 乱数 ÷ randomRange`。0 以上 1 未満）が入った候補を当選にする。
/// 重みの合計と累積は同じ順で左から足すので、確率（`Probability.odds(of:)`）と区間の幅が一致する。
/// 乱数は `randomIndex`（`0..<上限` の整数）で注入する（TypeScript の `RandomInt` と同じ形）。
nonisolated enum GachaDraw {
    /// 乱数で引く整数の範囲（`0..<randomRange`。TypeScript の `DRAW_RANDOM_RANGE`）。
    ///
    /// `crypto.randomInt` の上限（範囲が 2^48 未満）に収まる 2 の累乗にして、`乱数 ÷ この値` を誤差なく求める
    static let randomRange = 1 << 47

    /// 抽選の対象の候補と重み（除外した候補を外し、ID 順に並べる。TypeScript の `drawEntriesOf`）
    /// - Parameters:
    ///   - candidates: ルームの候補（どの順でもよい）
    ///   - mode: ルームのいいねの効き方
    ///   - excludedIDs: 引き直しで除外された候補の ID（`rooms.excludedCandidateIds`）
    static func entries(of candidates: [OddsInput], mode: LikeMode, excluding excludedIDs: Set<String>) -> [DrawEntry] {
        Probability.eligibleInIDOrder(candidates, id: \.id, excluding: excludedIDs).map {
            DrawEntry(id: $0.id, weight: Probability.weight(likeCount: $0.likeCount, mode: mode))
        }
    }

    /// 重み付きで 1 件を選ぶ（`entries` の順に累積を足す。並べ替えない。TypeScript の `pickWeighted`）。
    ///
    /// 重みが 0 以下の候補は区間の幅が 0 なので当選しない。
    /// 候補が無い・重みの合計が 0 以下・乱数が範囲の外のときは nil（呼ぶ側で候補が 0 件なら先に断る。TypeScript は投げる）
    /// - Parameters:
    ///   - entries: 抽選の対象の候補（ID 順に並べたもの。`entries(of:mode:excluding:)`）
    ///   - randomIndex: 乱数（`randomRange` を渡して `0..<randomRange` の整数を返す）
    /// - Returns: 当選した候補の ID
    static func pick(_ entries: [DrawEntry], randomIndex: (Int) -> Int) -> String? {
        let total = entries.reduce(0) { $0 + $1.weight }
        guard !entries.isEmpty, total > 0 else {
            return nil
        }
        let value = randomIndex(randomRange)
        guard (0..<randomRange).contains(value) else {
            return nil
        }
        let target = (Double(value) / Double(randomRange)) * total
        var cumulative = 0.0
        var lastPositive: String?
        for entry in entries where entry.weight > 0 {
            cumulative += entry.weight
            lastPositive = entry.id
            if target < cumulative {
                return entry.id
            }
        }
        // 丸めで target が累積の最後に届いた（u < 1 なので通常は起きない）ときは、最後の重みのある候補にする
        return lastPositive
    }

    /// ルームの候補から抽選する（TypeScript の `drawCandidate`）。
    /// - Parameters:
    ///   - candidates: ルームの候補（どの順でもよい）
    ///   - mode: ルームのいいねの効き方
    ///   - excludedIDs: 引き直しで除外された候補の ID
    ///   - randomIndex: 乱数
    /// - Returns: 抽選の結果。抽選の対象の候補が 0 件なら nil（`no-candidates` で断る）
    static func draw(
        _ candidates: [OddsInput],
        mode: LikeMode,
        excluding excludedIDs: Set<String>,
        randomIndex: (Int) -> Int
    ) -> DrawOutcome? {
        let entries = entries(of: candidates, mode: mode, excluding: excludedIDs)
        guard let candidateID = pick(entries, randomIndex: randomIndex) else {
            return nil
        }
        let odds = Probability.odds(of: candidates, mode: mode, excluding: excludedIDs)
        return DrawOutcome(
            candidateID: candidateID,
            probability: odds[candidateID]?.probability ?? 0,
            weights: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.weight) })
        )
    }
}
