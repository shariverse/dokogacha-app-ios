//
//  WinRarityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// レア当選（F-42「当選確率 < 平均確率 × 0.85」）の境目を確かめる
struct WinRarityTests {
    /// 比 0.85 ちょうどはレア当選にせず、それより小さければレア当選
    @Test
    func boundaryAtExactly085() {
        // 候補 20 件の平均は 5%。0.85 倍は 4.25%
        #expect(!WinRarity.isRare(probability: 0.0425, candidateCount: 20))
        #expect(WinRarity.isRare(probability: 0.0424, candidateCount: 20))
        #expect(!WinRarity.isRare(probability: 0.0426, candidateCount: 20))
        // 重みから作った確率（割り算の誤差を含む）でも、比 0.85 ちょうどはレア当選に落ちない（ほかの 19 件は重み 1）
        let winnerWeight = 0.85 * 19 / (20 - 0.85)
        let probabilities = Probability.probabilities(weights: [winnerWeight] + Array(repeating: 1, count: 19))
        #expect(!WinRarity.isRare(probability: probabilities[0], candidateCount: 20))
        #expect(WinRarity.isRare(probability: probabilities[0] * 0.999, candidateCount: 20))
    }

    /// 06 の §2 の例（いいね [4,3,3,2,2,1,1,0]）: 最も少ない候補（5%・平均 12.5%）はレア当選、11% は 0.88 倍でレア当選でない
    @Test
    func boostExample() {
        let weights = [4, 3, 3, 2, 2, 1, 1, 0].map { Probability.weight(likeCount: $0, mode: .boost) }
        let probabilities = Probability.probabilities(weights: weights)
        let rare = probabilities.map { WinRarity.isRare(probability: $0, candidateCount: weights.count) }
        #expect(rare == [false, false, false, false, false, false, false, true])
    }

    /// みんな平等はどの件数でもレア当選にならない（表示 % の丸めに引きずられない。67 件は 1.49% で表示は 1%）
    @Test(arguments: [1, 2, 3, 7, 67, 134, 200])
    func equalModeIsNeverRare(_ count: Int) {
        let probabilities = Probability.probabilities(weights: Array(repeating: 1, count: count))
        #expect(probabilities.allSatisfy { !WinRarity.isRare(probability: $0, candidateCount: count) })
    }

    /// 候補の数が 0 以下・確率が数でないときはレア当選にしない
    @Test
    func brokenInputsAreNotRare() {
        #expect(!WinRarity.isRare(probability: 0.01, candidateCount: 0))
        #expect(!WinRarity.isRare(probability: .nan, candidateCount: 3))
    }

    /// 抽選の記録からは、重みのスナップショットの件数を候補の数にする
    @Test
    func drawRecordUsesWeightCount() {
        let rare = Draw(
            candidateId: "c1",
            probability: 0.1,
            weights: ["c0": 3, "c1": 1, "c2": 3, "c3": 3],
            drawnBy: "u",
            drawnByName: "はるか",
            isReroll: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(WinRarity.isRare(rare))
        var common = rare
        common.probability = 0.3
        #expect(!WinRarity.isRare(common))
    }
}
