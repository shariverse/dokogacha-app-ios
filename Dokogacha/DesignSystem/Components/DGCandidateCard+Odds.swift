//
//  DGCandidateCard+Odds.swift
//  Dokogacha
//
//  出やすさの計算の結果（`Domain/Logic/Probability.swift`）から、候補カード・メーターに渡す見た目を引く。
//

import SwiftUI

// 部品（`DGCandidateCard`・`DGProbabilityMeter`）はドメインの型に依存させず、表示に要る値だけを受け取る。
// ドメインの判定の結果から部品の型への対応は、このファイルだけに置く。
// switch で全件を書くので、レベルや強調の種類を足したのに見た目を書き忘れるとビルドが通らない。

nonisolated extension DGLevelStyle {
    /// 出やすさのレベル（F-22）のラベルと色を返す。
    /// - Parameter level: `Probability.level` などで決めたレベル
    /// - Returns: そのレベルのチップ・バー・数字の見た目
    static func of(_ level: ProbabilityLevel) -> Self {
        switch level {
        case .flat: .flat
        case .high: .high
        case .mid: .mid
        case .low: .low
        }
    }
}

nonisolated extension DGCandidateCard.Highlight {
    /// 人気の強調（F-23）の判定の結果から、カードのリボンの種類を作る。
    /// - Parameter highlight: `Probability.highlight` の結果
    init(_ highlight: PopularityHighlight) {
        switch highlight {
        case .popular: self = .popular
        case .allLiked: self = .allLiked
        }
    }
}
