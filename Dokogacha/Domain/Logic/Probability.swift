//
//  Probability.swift
//  Dokogacha
//
//  出やすさ（02 の §4.2〜4.4・F-21〜F-23）の重み・確率・表示 %・レベル・人気の判定。
//  TypeScript 側の `backend/functions/src/domain/probability.ts` と同じ式で、06 の §2 の同じケースを両方で確かめる。
//  抽選（`drawGacha`）はサーバーで行うので、アプリはこの計算を表示にだけ使う。
//

import Foundation

/// 出やすさのレベル（F-22。02 の §4.3）。
nonisolated enum ProbabilityLevel: CaseIterable, Sendable {
    /// みんな平等モード（どの候補も同じ確率）
    case flat
    /// 出やすい（比 ≥ 1.2）
    case high
    /// ふつう（0.85 ≤ 比 < 1.2）
    case mid
    /// レア（比 < 0.85）
    case low
}

/// 人気の強調（F-23。02 の §4.4）。
nonisolated enum PopularityHighlight: CaseIterable, Sendable {
    /// 投稿者以外のメンバーの 6 割以上がいいね（「みんな推し」）
    case popular
    /// 投稿者以外のメンバー全員がいいね（「全員いいね」）
    case allLiked
}

/// 出やすさを計算する候補 1 件分の入力。
nonisolated struct OddsInput: Equatable, Sendable {
    /// 候補の ID（`candidates/{candidateId}`）
    let id: String
    /// いいね数（`likedBy` の数）
    let likeCount: Int
}

/// 候補 1 件分の出やすさ。
nonisolated struct CandidateOdds: Equatable, Sendable {
    /// 重み（F-21）
    let weight: Double
    /// 確率（0〜1。重み ÷ 抽選の対象の重みの合計）
    let probability: Double
    /// 表示 %（`round(確率 × 100)`）
    let displayPercent: Int
    /// レベル（F-22）
    let level: ProbabilityLevel
}

/// ルームの全候補の出やすさ。
nonisolated struct OddsTable: Equatable, Sendable {
    /// 候補の ID ごとの出やすさ。抽選の対象から外れた候補（引き直しの除外）は入らない
    let odds: [String: CandidateOdds]
    /// 抽選の対象の候補の中で最大の表示 %（メーターの長さ `DGProbabilityMeterRule.fillFraction` に渡す）。候補が無ければ 0
    let maxDisplayPercent: Int

    /// 候補の出やすさ。抽選の対象から外れた候補・知らない ID は nil
    subscript(id: String) -> CandidateOdds? {
        odds[id]
    }
}

/// 出やすさ（F-21〜F-23）の計算。
///
/// どれも副作用の無い純粋な関数。同じ式を TypeScript（`probability.ts`）でも持つので、計算の順番
/// （重みの合計は渡した順に左から足す・丸めは 0.5 を切り上げる）までそろえ、浮動小数点の結果を一致させる。
nonisolated enum Probability {
    /// 候補の重み（F-21）。
    ///
    /// 共感ブーストは `1 + sqrt(いいね数)`、みんな平等は `1`。いいね数が負の値で来ても（壊れたデータ）0 とみなす。
    /// - Parameters:
    ///   - likeCount: いいね数
    ///   - mode: ルームのいいねの効き方
    static func weight(likeCount: Int, mode: LikeMode) -> Double {
        switch mode {
        case .boost: 1 + Double(max(likeCount, 0)).squareRoot()
        case .equal: 1
        }
    }

    /// 重みから確率を出す（F-21「確率 = 重み ÷ Σ重み」）。
    ///
    /// 合計は渡した順に左から足す（TypeScript と同じ順にして結果を一致させる）。合計が 0 以下なら（候補が無いなど）すべて 0。
    /// - Parameter weights: 抽選の対象の候補の重み
    /// - Returns: 同じ順の確率
    static func probabilities(weights: [Double]) -> [Double] {
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return weights.map { _ in 0 }
        }
        return weights.map { $0 / total }
    }

    /// 確率を表示 % にする（F-21「表示% = round(確率 × 100)」）。
    ///
    /// 0.5 は切り上げる（TypeScript の `Math.round` と同じ。確率は 0 以上なので、0 から遠い方への丸めと結果が同じ）。
    /// 02 のとおり、全候補の表示 % の合計が 100 にならなくても合わせない。
    /// - Parameter probability: 確率（0〜1）
    static func displayPercent(probability: Double) -> Int {
        Int((probability * 100).rounded(.toNearestOrAwayFromZero))
    }

    /// 出やすさのレベル（F-22）。
    ///
    /// みんな平等モードは常に「平等」。共感ブーストは「比 = 表示% ÷ 平均%（`100 / 候補数`）」で決める。
    /// 比 × 100 は `表示% × 候補数` の整数になるので、整数どうしで境目（`DomainConstants.Odds`）と比べ、
    /// 浮動小数点の誤差で「1.2 ちょうど」「0.85 ちょうど」が下のレベルに落ちないようにする。
    /// - Parameters:
    ///   - displayPercent: この候補の表示 %
    ///   - candidateCount: 抽選の対象の候補の数（平均 % の分母）
    ///   - mode: ルームのいいねの効き方
    static func level(displayPercent: Int, candidateCount: Int, mode: LikeMode) -> ProbabilityLevel {
        guard mode == .boost else {
            return .flat
        }
        let ratioPercent = displayPercent * candidateCount
        if ratioPercent >= DomainConstants.Odds.highRatioPercent {
            return .high
        }
        if ratioPercent >= DomainConstants.Odds.midRatioPercent {
            return .mid
        }
        return .low
    }

    /// ルームの全候補の出やすさ（F-21・F-22）をまとめて出す。
    ///
    /// 引き直しで除外された候補（`rooms.excludedCandidateIds`）は、`drawGacha` と同じく抽選の対象から外し、
    /// 重みの合計にも平均 % の分母にも入れない（表に入らない）。除外した候補を画面でどう見せるかは画面の側で決める。
    /// - Parameters:
    ///   - candidates: 候補（並びの順に重みを足す）
    ///   - mode: ルームのいいねの効き方
    ///   - excludedIDs: 抽選の対象から外す候補の ID
    static func odds(of candidates: [OddsInput], mode: LikeMode, excluding excludedIDs: Set<String> = []) -> OddsTable {
        let eligible = candidates.filter { !excludedIDs.contains($0.id) }
        let weights = eligible.map { weight(likeCount: $0.likeCount, mode: mode) }
        let chances = probabilities(weights: weights)
        var odds: [String: CandidateOdds] = [:]
        for (index, candidate) in eligible.enumerated() {
            let percent = displayPercent(probability: chances[index])
            odds[candidate.id] = CandidateOdds(
                weight: weights[index],
                probability: chances[index],
                displayPercent: percent,
                level: level(displayPercent: percent, candidateCount: eligible.count, mode: mode)
            )
        }
        return OddsTable(odds: odds, maxDisplayPercent: odds.values.map(\.displayPercent).max() ?? 0)
    }

    /// 人気の強調（F-23）。
    ///
    /// 投稿者を除いたメンバー数 `n' = メンバー数 − 1` に対し、「全員いいね」は `いいね数 ≥ n'（かつ n' ≥ 2）`、
    /// 「みんな推し」は `いいね数 ≥ ceil(n' × 0.6)（かついいね数 ≥ 2）`。両方に当てはまるときは「全員いいね」を優先する。
    /// 基準の値は `DomainConstants.Popularity`（06 の §4 の仮決め）。
    /// - Parameters:
    ///   - likeCount: いいね数
    ///   - memberCount: ルームのメンバー数（投稿者を含む）
    /// - Returns: 強調しないなら nil
    static func highlight(likeCount: Int, memberCount: Int) -> PopularityHighlight? {
        let otherMembers = memberCount - 1
        if otherMembers >= DomainConstants.Popularity.allLikedMinOtherMembers, likeCount >= otherMembers {
            return .allLiked
        }
        let popularThreshold = Int((Double(otherMembers) * DomainConstants.Popularity.popularRatio).rounded(.up))
        if likeCount >= DomainConstants.Popularity.popularMinLikes, likeCount >= popularThreshold {
            return .popular
        }
        return nil
    }
}
