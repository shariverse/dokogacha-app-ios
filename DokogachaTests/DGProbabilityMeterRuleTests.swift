//
//  DGProbabilityMeterRuleTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// 出やすさのメーターのバーの長さ（`DGProbabilityMeterRule`）を確かめる。
struct DGProbabilityMeterRuleTests {
    /// 02 の F-21 の例（いいね [4, 3, 3, 2, 2, 1, 1, 0] → 表示 [16, 15, 15, 13, 13, 11, 11, 5]%）の、表示 % とバーの長さの組
    nonisolated static let exampleCases: [(percent: Int, fraction: Double)] = [
        (16, 1),
        (15, 15.0 / 16.0),
        (13, 13.0 / 16.0),
        (11, 11.0 / 16.0),
        (5, 5.0 / 16.0)
    ]

    /// 表示 % ÷ 最大の表示 % がバーの長さになり、最大の候補は満タンになる
    @Test(arguments: Self.exampleCases)
    func fractionIsRatioToMaximum(percent: Int, fraction: Double) {
        #expect(DGProbabilityMeterRule.fillFraction(percent: percent, maxPercent: 16) == fraction)
    }

    /// みんな平等モード（全候補が同じ %）では全候補が満タン
    @Test
    func equalModeFillsAll() {
        #expect(DGProbabilityMeterRule.fillFraction(percent: 13, maxPercent: 13) == 1)
    }

    /// 最大が 0 以下なら 0 にする（0 で割らない）
    @Test
    func zeroMaximumIsEmpty() {
        #expect(DGProbabilityMeterRule.fillFraction(percent: 0, maxPercent: 0) == 0)
        #expect(DGProbabilityMeterRule.fillFraction(percent: 5, maxPercent: -1) == 0)
    }

    /// 範囲の外の値は 0〜1 に収める
    @Test
    func outOfRangeIsClamped() {
        #expect(DGProbabilityMeterRule.fillFraction(percent: 20, maxPercent: 16) == 1)
        #expect(DGProbabilityMeterRule.fillFraction(percent: -3, maxPercent: 16) == 0)
    }
}
