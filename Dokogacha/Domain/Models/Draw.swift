//
//  Draw.swift
//  Dokogacha
//

import Foundation

/// 抽選の記録（`rooms/{roomId}/draws/{drawId}`。05 の §3）。`drawGacha` だけが作る。
nonisolated struct Draw: Codable, Sendable, Equatable {
    /// 当選した候補の ID
    var candidateId: String
    /// 当選時の確率（0〜1）
    var probability: Double
    /// 抽選時の重みのスナップショット（候補の ID → 重み）
    var weights: [String: Double]
    /// 回した人の uid
    var drawnBy: String
    /// 回した人の表示名（「◯◯さんがガチャを回しました」に出す）
    var drawnByName: String
    /// 引き直しの抽選か
    var isReroll: Bool
    /// 抽選の日時
    var createdAt: Date
}
