//
//  DGStepperRuleTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// Stepper の増減の判定（`DGStepperRule`）を確かめる。範囲は S-03 の投稿数（1〜10）。
struct DGStepperRuleTests {
    /// S-03 の「1〜10件」
    nonisolated static let range = 1...10

    /// 範囲の中では 1 ずつ増減できる
    @Test
    func stepsInsideRange() {
        #expect(DGStepperRule.canDecrement(3, in: Self.range))
        #expect(DGStepperRule.canIncrement(3, in: Self.range))
        #expect(DGStepperRule.decremented(3, in: Self.range) == 2)
        #expect(DGStepperRule.incremented(3, in: Self.range) == 4)
    }

    /// 下限では減らせず、減らしても下限のまま
    @Test
    func stopsAtLowerBound() {
        #expect(!DGStepperRule.canDecrement(1, in: Self.range))
        #expect(DGStepperRule.canIncrement(1, in: Self.range))
        #expect(DGStepperRule.decremented(1, in: Self.range) == 1)
    }

    /// 上限では増やせず、増やしても上限のまま
    @Test
    func stopsAtUpperBound() {
        #expect(DGStepperRule.canDecrement(10, in: Self.range))
        #expect(!DGStepperRule.canIncrement(10, in: Self.range))
        #expect(DGStepperRule.incremented(10, in: Self.range) == 10)
    }

    /// S-12 の「現在値未満は選べない」: 下限を現在値にした範囲では、現在値より下げられない
    @Test
    func currentValueAsLowerBound() {
        let range = 4...10
        #expect(!DGStepperRule.canDecrement(4, in: range))
        #expect(DGStepperRule.decremented(4, in: range) == 4)
        #expect(DGStepperRule.incremented(4, in: range) == 5)
    }

    /// 範囲の外の値は、操作すると範囲の中に戻る
    @Test
    func outOfRangeValueIsClamped() {
        #expect(DGStepperRule.incremented(0, in: Self.range) == 1)
        #expect(DGStepperRule.decremented(12, in: Self.range) == 10)
        #expect(DGStepperRule.clamped(-5, in: Self.range) == 1)
        #expect(DGStepperRule.clamped(5, in: Self.range) == 5)
    }

    /// 範囲が 1 つの値だけなら、どちらにも動かせない
    @Test
    func singleValueRange() {
        #expect(!DGStepperRule.canDecrement(10, in: 10...10))
        #expect(!DGStepperRule.canIncrement(10, in: 10...10))
    }
}
