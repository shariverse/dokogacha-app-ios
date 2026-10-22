//
//  GachaDrawTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 抽選の重み付きの選択（F-40）を確かめる（06 の §2「抽選」: 固定シードで同じ結果／1 万回試行の当選率が理論値 ±2%／除外リストの候補は当選しない）。
///
/// TypeScript 側の `backend/functions/src/domain/draw.test.ts` と同じケース（同じシードの乱数で同じ当選の並び）。片方を変えたら両方を変える。
struct GachaDrawTests {
    /// 02 の §4.2 の例のいいね数
    nonisolated static let exampleLikes = [4, 3, 3, 2, 2, 1, 1, 0]
    /// 1 万回の試行
    static let trials = 10_000
    /// 当選率と理論値の差の許容（02 の F-40 の AC「理論値±2%以内」。確率の差で 0.02）
    static let tolerance = 0.02
    /// 固定のシード（TypeScript と同じ値）
    static let seed: UInt32 = 20_261_022
    /// 固定のシードで最初の 12 回に当選する候補（02 の例・共感ブースト。TypeScript の `SEEDED_WINNERS` と同じ）
    static let seededWinners = ["c3", "c1", "c3", "c2", "c0", "c2", "c1", "c5", "c2", "c2", "c5", "c3"]

    /// いいね数の一覧から、`c0`・`c1`… の ID の入力を作る
    static func inputs(_ likes: [Int]) -> [OddsInput] {
        likes.enumerated().map { OddsInput(id: "c\($0.offset)", likeCount: $0.element) }
    }

    /// シードから同じ並びの乱数を作る（mulberry32。テストだけで使う。TypeScript の `seeded` と同じ式）。
    ///
    /// `randomIndex(max)` は `floor(0 以上 1 未満の値 × max)`。TypeScript の `Math.imul` と `>>>` は、`UInt32` の `&*`・`>>` と同じビットになる
    static func seeded(_ seed: UInt32) -> (Int) -> Int {
        var state = seed
        return { max in
            state = state &+ 0x6D2B_79F5
            var value = state
            value = (value ^ (value >> 15)) &* (value | 1)
            value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
            let unit = Double(value ^ (value >> 14)) / 4_294_967_296
            return Int((unit * Double(max)).rounded(.down))
        }
    }

    /// 決まった値を返す乱数
    static func fixed(_ value: Int) -> (Int) -> Int {
        { _ in value }
    }

    /// `trials` 回抽選して、候補の ID ごとの当選数を数える
    static func countWins(_ entries: [DrawEntry], randomIndex: (Int) -> Int, trials: Int) -> [String: Int] {
        var wins: [String: Int] = [:]
        for _ in 0..<trials {
            guard let winner = GachaDraw.pick(entries, randomIndex: randomIndex) else {
                Issue.record("当選が無い")
                return wins
            }
            wins[winner, default: 0] += 1
        }
        return wins
    }

    /// 06 の §2: 固定シードで同じ結果（同じシードなら同じ並び。TypeScript と同じ当選の並び）
    @Test
    func seededDrawIsReproducible() {
        let entries = GachaDraw.entries(of: Self.inputs(Self.exampleLikes), mode: .boost, excluding: [])
        let first = Self.seeded(Self.seed)
        let second = Self.seeded(Self.seed)
        let winners = (0..<Self.seededWinners.count).map { _ in GachaDraw.pick(entries, randomIndex: first) }
        #expect(winners == Self.seededWinners)
        #expect((0..<Self.seededWinners.count).map { _ in GachaDraw.pick(entries, randomIndex: second) } == winners)
    }

    /// 06 の §2: 1 万回試行の当選率が理論値 ±2% 以内
    @Test(arguments: LikeMode.allCases)
    func winRatesMatchProbabilities(mode: LikeMode) {
        let candidates = Self.inputs(Self.exampleLikes)
        let entries = GachaDraw.entries(of: candidates, mode: mode, excluding: [])
        let wins = Self.countWins(entries, randomIndex: Self.seeded(Self.seed), trials: Self.trials)
        for (id, odds) in Probability.odds(of: candidates, mode: mode).odds {
            #expect(abs(Double(wins[id, default: 0]) / Double(Self.trials) - odds.probability) <= Self.tolerance)
        }
    }

    /// いいねが多い候補ほど当選しやすい（共感ブーストで、いいね 4 の候補はいいね 0 の候補より多く当選する）
    @Test
    func moreLikesWinMoreOften() {
        let entries = GachaDraw.entries(of: Self.inputs(Self.exampleLikes), mode: .boost, excluding: [])
        let wins = Self.countWins(entries, randomIndex: Self.seeded(Self.seed), trials: Self.trials)
        #expect(wins["c0", default: 0] > wins["c7", default: 0])
    }

    /// 06 の §2: 除外リストの候補は当選しない（1 万回のうち 0 回）
    @Test
    func excludedCandidatesNeverWin() {
        let entries = GachaDraw.entries(of: Self.inputs(Self.exampleLikes), mode: .boost, excluding: ["c0", "c3"])
        #expect(entries.map(\.id) == ["c1", "c2", "c4", "c5", "c6", "c7"])
        let wins = Self.countWins(entries, randomIndex: Self.seeded(Self.seed), trials: Self.trials)
        #expect(wins["c0"] == nil)
        #expect(wins["c3"] == nil)
        // 乱数が 0（区間の先頭）でも、除外した先頭の c0 ではなく次の c1 が当たる
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(0)) == "c1")
    }

    /// 境目: 重み [1, 2, 1] の区間は [0, 1/4)・[1/4, 3/4)・[3/4, 1)（TypeScript と同じ値）
    @Test
    func boundaries() {
        let entries = [DrawEntry(id: "a", weight: 1), DrawEntry(id: "b", weight: 2), DrawEntry(id: "c", weight: 1)]
        let quarter = GachaDraw.randomRange / 4
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(0)) == "a")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(quarter - 1)) == "a")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(quarter)) == "b")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(quarter * 3 - 1)) == "b")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(quarter * 3)) == "c")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(GachaDraw.randomRange - 1)) == "c")
    }

    /// 候補 1 件なら、乱数によらずその候補が当選する
    @Test
    func singleCandidateAlwaysWins() {
        let entries = GachaDraw.entries(of: Self.inputs([3]), mode: .boost, excluding: [])
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(0)) == "c0")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(GachaDraw.randomRange - 1)) == "c0")
    }

    /// 重みが 0 の候補は当選しない（区間の幅が 0）
    @Test
    func zeroWeightNeverWins() {
        let entries = [DrawEntry(id: "a", weight: 0), DrawEntry(id: "b", weight: 1), DrawEntry(id: "c", weight: 0)]
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(0)) == "b")
        #expect(GachaDraw.pick(entries, randomIndex: Self.fixed(GachaDraw.randomRange - 1)) == "b")
    }

    /// 渡す順によらず、候補の ID 順に区間を並べる
    @Test
    func entriesAreInIDOrder() {
        let candidates = Self.inputs(Self.exampleLikes)
        let reversed = GachaDraw.entries(of: Array(candidates.reversed()), mode: .boost, excluding: [])
        #expect(reversed == GachaDraw.entries(of: candidates, mode: .boost, excluding: []))
        #expect(GachaDraw.pick(reversed, randomIndex: Self.fixed(0)) == "c0")
    }

    /// 乱数に `randomRange`（2^47。TypeScript の `DRAW_RANDOM_RANGE`）を渡す
    @Test
    func requestsRandomRange() {
        var requested: [Int] = []
        _ = GachaDraw.pick([DrawEntry(id: "a", weight: 1)]) { max in
            requested.append(max)
            return 0
        }
        #expect(requested == [1 << 47])
    }

    /// 候補が無い・乱数が範囲の外のときは nil（TypeScript は投げる）
    @Test
    func invalidInputsGiveNil() {
        #expect(GachaDraw.pick([], randomIndex: Self.fixed(0)) == nil)
        #expect(GachaDraw.pick([DrawEntry(id: "a", weight: 0)], randomIndex: Self.fixed(0)) == nil)
        for value in [-1, GachaDraw.randomRange] {
            #expect(GachaDraw.pick([DrawEntry(id: "a", weight: 1)], randomIndex: Self.fixed(value)) == nil)
        }
    }

    // MARK: draw（擬似のサーバーの drawGacha が書く抽選の記録の値）

    /// 当選時の確率は出やすさの表と同じ値で、重みのスナップショットは抽選の対象の候補だけ
    @Test
    func drawRecordsProbabilityAndWeights() throws {
        let candidates = Self.inputs(Self.exampleLikes)
        let outcome = try #require(GachaDraw.draw(candidates, mode: .boost, excluding: ["c7"], randomIndex: Self.fixed(0)))
        #expect(outcome.candidateID == "c0")
        #expect(outcome.probability == Probability.odds(of: candidates, mode: .boost, excluding: ["c7"])["c0"]?.probability)
        #expect(outcome.weights.keys.sorted() == ["c0", "c1", "c2", "c3", "c4", "c5", "c6"])
        #expect(outcome.weights["c0"] == 3)
    }

    /// みんな平等では、どの候補も重み 1・確率 1/候補数
    @Test
    func equalModeDraw() {
        let outcome = GachaDraw.draw(
            Self.inputs([5, 0, 0, 0]), mode: .equal, excluding: [], randomIndex: Self.fixed(GachaDraw.randomRange - 1)
        )
        #expect(outcome == DrawOutcome(candidateID: "c3", probability: 0.25, weights: ["c0": 1, "c1": 1, "c2": 1, "c3": 1]))
    }

    /// 候補が無い・すべて除外したときは nil（no-candidates で断る）
    @Test
    func drawWithoutCandidates() {
        #expect(GachaDraw.draw([], mode: .boost, excluding: [], randomIndex: Self.fixed(0)) == nil)
        #expect(GachaDraw.draw(Self.inputs([1, 2]), mode: .boost, excluding: ["c0", "c1"], randomIndex: Self.fixed(0)) == nil)
    }
}
