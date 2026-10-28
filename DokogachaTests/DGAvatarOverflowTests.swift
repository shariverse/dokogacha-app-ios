//
//  DGAvatarOverflowTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// アバターを並べる数と「+N」の数（`DGAvatarOverflow`）を確かめる。上限は S-07 の 6 人。
struct DGAvatarOverflowTests {
    /// 人数と、並べる数・「+N」の数の組
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        /// メンバーの人数
        let total: Int
        /// 並べるアバターの数
        let visible: Int
        /// 「+N」にまとめる数
        let hidden: Int

        var testDescription: String {
            "\(total) 人 → \(visible) 人＋\(hidden)"
        }
    }

    /// 上限 6 人のときの組
    nonisolated static let cases: [Case] = [
        Case(total: 0, visible: 0, hidden: 0),
        Case(total: 1, visible: 1, hidden: 0),
        Case(total: 6, visible: 6, hidden: 0),
        Case(total: 7, visible: 6, hidden: 1),
        Case(total: 20, visible: 6, hidden: 14)
    ]

    /// 6 人までは全員並べ、7 人以上は 6 人＋「+N」にする
    @Test(arguments: Self.cases)
    func splitsAtLimit(_ testCase: Case) {
        let overflow = DGAvatarOverflow(total: testCase.total, limit: 6)
        #expect(overflow.visible == testCase.visible)
        #expect(overflow.hidden == testCase.hidden)
    }

    /// 負の値が来ても、数は 0 未満にならない
    @Test
    func negativeValuesBecomeZero() {
        let noMembers = DGAvatarOverflow(total: -1, limit: 6)
        #expect(noMembers.visible == 0)
        #expect(noMembers.hidden == 0)
        let noLimit = DGAvatarOverflow(total: 3, limit: -1)
        #expect(noLimit.visible == 0)
        #expect(noLimit.hidden == 3)
    }
}
