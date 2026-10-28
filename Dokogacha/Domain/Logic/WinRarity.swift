//
//  WinRarity.swift
//  Dokogacha
//

import Foundation

/// レア当選（F-42。02 の §6.3「当選確率 < 平均確率 × 0.85 のとき『レア当選』バッジを表示」）の判定。
///
/// 当選確率は抽選の記録（`draws.probability`）の値、平均確率は `1 ÷ 抽選の対象の候補の数`（記録の重みのスナップショット `weights` の件数）。
/// 表示 %（丸めた値）ではなく確率そのもので比べる。表示 % で比べると、みんな平等で候補が多いとき（67 件で 1.49% → 1%）に
/// 丸めでレア当選になってしまうため。比は `当選確率 × 候補の数` で作り、割り算の誤差を `DomainConstants.Odds.rareWinTolerance` で吸収する。
/// TypeScript には同じ判定を持たない（サーバーはレア当選を使わない）。
nonisolated enum WinRarity {
    /// レア当選か
    /// - Parameters:
    ///   - probability: 当選時の確率（0〜1）
    ///   - candidateCount: 抽選の対象だった候補の数。0 以下なら（壊れたデータ）レア当選にしない
    static func isRare(probability: Double, candidateCount: Int) -> Bool {
        guard candidateCount > 0, probability.isFinite else {
            return false
        }
        let ratio = probability * Double(candidateCount)
        return ratio < DomainConstants.Odds.rareWinRatio - DomainConstants.Odds.rareWinTolerance
    }

    /// 抽選の記録がレア当選か（候補の数は重みのスナップショットの件数）
    static func isRare(_ draw: Draw) -> Bool {
        isRare(probability: draw.probability, candidateCount: draw.weights.count)
    }
}
