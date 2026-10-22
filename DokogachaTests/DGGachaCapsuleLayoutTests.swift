//
//  DGGachaCapsuleLayoutTests.swift
//  DokogachaTests
//

import CoreGraphics
@testable import Dokogacha
import Testing

/// ガチャのドームのカプセルの並べ方（`DGGachaCapsuleLayout`）を確かめる。
struct DGGachaCapsuleLayoutTests {
    /// 候補の数と描くカプセルの数の組（0 未満は 0、50 を超えたら 50）
    nonisolated static let countCases: [(count: Int, visible: Int)] = [
        (-1, 0),
        (0, 0),
        (1, 1),
        (8, 8),
        (50, 50),
        (51, 50),
        (120, 50)
    ]

    /// 描く数は 0〜50 に収まり、置き場所もその数だけ返す
    @Test(arguments: Self.countCases)
    func visibleCountIsClamped(count: Int, visible: Int) {
        #expect(DGGachaCapsuleLayout.visibleCount(for: count) == visible)
        #expect(DGGachaCapsuleLayout.placements(count: count).count == visible)
    }

    /// プロトタイプの式（線の内側の左上 x = 22 + (i × 61) mod 160、y = 120 + (i × 37) mod 80、傾き (i × 53) mod 360）と同じ位置になる。
    /// 中心はドームの線（5）と半径（20）を足した外形の左上からの位置
    @Test
    func matchesPrototypeFormula() throws {
        let placements = DGGachaCapsuleLayout.placements(count: 8)
        let first = try #require(placements.first)
        #expect(first.center == CGPoint(x: 47, y: 145))
        #expect(first.rotationDegrees == 0)
        // i = 3: x = 22 + 183 mod 160 = 45、y = 120 + 111 mod 80 = 151、傾き 159
        #expect(placements[3].center == CGPoint(x: 70, y: 176))
        #expect(placements[3].rotationDegrees == 159)
        // i = 7: x = 22 + 427 mod 160 = 129、y = 120 + 259 mod 80 = 139、傾き 371 mod 360 = 11
        #expect(placements[7].center == CGPoint(x: 154, y: 164))
        #expect(placements[7].rotationDegrees == 11)
    }

    /// 番号は描く順に 0 から並び、同じ数なら何度呼んでも同じ並びになる（乱数を使わない）
    @Test
    func isDeterministicAndOrdered() {
        let placements = DGGachaCapsuleLayout.placements(count: 50)
        #expect(placements.map(\.index) == Array(0..<50))
        #expect(placements == DGGachaCapsuleLayout.placements(count: 50))
    }

    /// どのカプセルもドームの下半分（線の内側から y 120〜200 の左上。04 の §4）に入り、横はドームの外形からはみ出さず、傾きは 0〜360 度未満
    @Test
    func staysInLowerHalfOfDome() {
        let radius = DGGachaCapsuleLayout.capsuleDiameter / 2
        let inset = DGBorder.machine + radius
        for placement in DGGachaCapsuleLayout.placements(count: 50) {
            let top = placement.center.y - inset
            #expect((120..<200).contains(top))
            #expect(placement.center.x - radius >= 0)
            #expect(placement.center.x + radius <= DGGachaCapsuleLayout.domeDiameter)
            #expect((0..<360).contains(placement.rotationDegrees))
        }
    }
}
