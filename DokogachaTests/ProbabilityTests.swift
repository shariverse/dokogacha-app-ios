//
//  ProbabilityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 出やすさ（F-21〜F-23）の重み・確率・表示 %・レベル・人気を確かめる（06 の §2 の「重み・確率」「レベル」「人気」）。
///
/// TypeScript 側の `backend/functions/src/domain/probability.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct ProbabilityTests {
    /// 02 の §4.2 の例のいいね数
    nonisolated static let exampleLikes = [4, 3, 3, 2, 2, 1, 1, 0]

    /// いいね数の一覧から、`c0`・`c1`… の ID の入力を作る
    static func inputs(_ likes: [Int]) -> [OddsInput] {
        likes.enumerated().map { OddsInput(id: "c\($0.offset)", likeCount: $0.element) }
    }

    /// 表の出やすさを、入力の順に並べる（除外した候補は nil）
    static func ordered(_ table: OddsTable, count: Int) -> [CandidateOdds?] {
        (0..<count).map { table["c\($0)"] }
    }

    /// 小数第 2 位で丸める
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    // MARK: 重み・確率（F-21）

    /// 02 の §4.2 の例: いいね [4,3,3,2,2,1,1,0] → 重み [3.00, 2.73, 2.73, 2.41, 2.41, 2.00, 2.00, 1.00]・合計 18.29・表示 [16,15,15,13,13,11,11,5]%
    @Test
    func boostExampleFromRequirements() throws {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .boost)
        let odds = try Self.ordered(table, count: Self.exampleLikes.count).map { try #require($0) }
        #expect(odds.map { Self.round2($0.weight) } == [3.00, 2.73, 2.73, 2.41, 2.41, 2.00, 2.00, 1.00])
        #expect(Self.round2(odds.map(\.weight).reduce(0, +)) == 18.29)
        #expect(odds.map(\.displayPercent) == [16, 15, 15, 13, 13, 11, 11, 5])
        #expect(table.maxDisplayPercent == 16)
    }

    /// 表示 % の合計は 100 にそろえない（02 の §4.2「合計が100にならなくてもよい」。例では 99）
    @Test
    func displayPercentsAreNotNormalized() {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .boost)
        #expect(table.odds.values.map(\.displayPercent).reduce(0, +) == 99)
        let equal = Probability.odds(of: Self.inputs([0, 0, 0]), mode: .equal)
        #expect(equal.odds.values.map(\.displayPercent) == [33, 33, 33])
    }

    /// 確率の合計は 1（丸める前）
    @Test
    func probabilitiesSumToOne() {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .boost)
        #expect(abs(table.odds.values.map(\.probability).reduce(0, +) - 1) < 1e-12)
    }

    /// みんな平等では、いいね数に関係なく全候補が同じ %
    @Test
    func equalModeGivesSamePercent() {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .equal)
        #expect(Set(table.odds.values.map(\.displayPercent)) == [13])
        #expect(Set(table.odds.values.map(\.weight)) == [1])
    }

    /// 候補 1 件なら、どちらのモードでも 100%
    @Test(arguments: LikeMode.allCases)
    func singleCandidateIsHundredPercent(mode: LikeMode) throws {
        let table = Probability.odds(of: Self.inputs([3]), mode: mode)
        #expect(try #require(table["c0"]).displayPercent == 100)
        #expect(table.maxDisplayPercent == 100)
    }

    /// 候補 0 件なら表は空で、最大の表示 % は 0
    @Test
    func noCandidates() {
        let table = Probability.odds(of: [], mode: .boost)
        #expect(table.odds.isEmpty)
        #expect(table.maxDisplayPercent == 0)
    }

    /// 全候補のいいね数が同じなら、共感ブーストでも同じ %（レベルは「ふつう」）
    @Test
    func sameLikesInBoost() {
        let table = Probability.odds(of: Self.inputs([2, 2, 2, 2]), mode: .boost)
        #expect(Set(table.odds.values.map(\.displayPercent)) == [25])
        #expect(Set(table.odds.values.map(\.level)) == [.mid])
    }

    /// 引き直しで除外した候補は、表に入らず、合計と平均の分母からも外れる
    @Test
    func excludedCandidatesAreLeftOut() throws {
        let table = Probability.odds(of: Self.inputs([4, 0, 0]), mode: .boost, excluding: ["c0"])
        #expect(table["c0"] == nil)
        #expect(try #require(table["c1"]).displayPercent == 50)
        #expect(try #require(table["c2"]).displayPercent == 50)
        #expect(try #require(table["c1"]).level == .mid)
        #expect(table.maxDisplayPercent == 50)
    }

    /// 全候補を除外したら表は空
    @Test
    func allExcluded() {
        let table = Probability.odds(of: Self.inputs([1, 2]), mode: .boost, excluding: ["c0", "c1"])
        #expect(table.odds.isEmpty)
        #expect(table.maxDisplayPercent == 0)
    }

    /// 重みの式: 共感ブーストは 1 + √いいね数、みんな平等は 1。負のいいね数は 0 とみなす
    @Test
    func weightFormula() {
        #expect(Probability.weight(likeCount: 0, mode: .boost) == 1)
        #expect(Probability.weight(likeCount: 4, mode: .boost) == 3)
        #expect(Probability.weight(likeCount: 9, mode: .equal) == 1)
        #expect(Probability.weight(likeCount: -1, mode: .boost) == 1)
    }

    /// 表示 % の丸めは 0.5 を切り上げる
    @Test
    func displayPercentRoundsHalfUp() {
        #expect(Probability.displayPercent(probability: 0.125) == 13)
        #expect(Probability.displayPercent(probability: 0.124) == 12)
        #expect(Probability.displayPercent(probability: 0) == 0)
        #expect(Probability.displayPercent(probability: 1) == 100)
    }

    /// 合計が 0 の重みからは確率 0
    @Test
    func zeroTotalWeight() {
        #expect(Probability.probabilities(weights: []).isEmpty)
        #expect(Probability.probabilities(weights: [0, 0]) == [0, 0])
    }

    // MARK: レベル（F-22）

    /// 06 の §2: 比 1.2 ちょうどで「出やすい」、0.85 ちょうどで「ふつう」、0.84 で「レア」（5 候補・平均 20%: 24% / 17%、4 候補・平均 25%: 21%）
    @Test
    func levelBoundaries() {
        #expect(Probability.level(displayPercent: 24, candidateCount: 5, mode: .boost) == .high)
        #expect(Probability.level(displayPercent: 23, candidateCount: 5, mode: .boost) == .mid)
        #expect(Probability.level(displayPercent: 17, candidateCount: 5, mode: .boost) == .mid)
        #expect(Probability.level(displayPercent: 21, candidateCount: 4, mode: .boost) == .low)
    }

    /// 平均 % が割り切れない候補数でも、比 1.2 ちょうどは「出やすい」（3 候補・平均 33.3…%: 40%）
    @Test
    func levelBoundaryWithRepeatingAverage() {
        #expect(Probability.level(displayPercent: 40, candidateCount: 3, mode: .boost) == .high)
        #expect(Probability.level(displayPercent: 39, candidateCount: 3, mode: .boost) == .mid)
    }

    /// 02 の §4.2 の例のレベル（平均 12.5%）
    @Test
    func levelsOfExample() {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .boost)
        let levels = Self.ordered(table, count: Self.exampleLikes.count).map { $0?.level }
        #expect(levels == [.high, .high, .high, .mid, .mid, .mid, .mid, .low])
    }

    /// みんな平等モードでは全候補が「平等」
    @Test
    func equalModeIsFlat() {
        let table = Probability.odds(of: Self.inputs(Self.exampleLikes), mode: .equal)
        #expect(Set(table.odds.values.map(\.level)) == [.flat])
        #expect(Probability.level(displayPercent: 100, candidateCount: 5, mode: .equal) == .flat)
    }

    // MARK: 人気（F-23）

    /// 06 の §2: 5 人ルーム（n' = 4）でいいね 2 → なし、3 → みんな推し、4 → 全員いいね
    @Test
    func fiveMemberRoom() {
        #expect(Probability.highlight(likeCount: 2, memberCount: 5) == nil)
        #expect(Probability.highlight(likeCount: 3, memberCount: 5) == .popular)
        #expect(Probability.highlight(likeCount: 4, memberCount: 5) == .allLiked)
    }

    /// 06 の §2: 2 人ルーム（n' = 1）ではいいね 1 でもリボンなし
    @Test
    func twoMemberRoom() {
        #expect(Probability.highlight(likeCount: 1, memberCount: 2) == nil)
        #expect(Probability.highlight(likeCount: 0, memberCount: 2) == nil)
    }

    /// 3 人ルーム（n' = 2）では、いいね 2 は「全員いいね」（みんな推しより優先）、1 はなし
    @Test
    func threeMemberRoom() {
        #expect(Probability.highlight(likeCount: 1, memberCount: 3) == nil)
        #expect(Probability.highlight(likeCount: 2, memberCount: 3) == .allLiked)
    }

    /// 1 人ルームではリボンなし
    @Test
    func soloRoom() {
        #expect(Probability.highlight(likeCount: 0, memberCount: 1) == nil)
    }

    /// 「みんな推し」の下限は、n' = 1〜19 のすべてで ceil(n' × 0.6)（整数で書いた (3n' + 4) / 5）と 2 の大きい方
    @Test
    func popularThresholdForAllRoomSizes() {
        for otherMembers in 1...(DomainConstants.Limits.maxMembers - 1) {
            let memberCount = otherMembers + 1
            let threshold = max((3 * otherMembers + 4) / 5, 2)
            for likes in 0...otherMembers {
                let expected: PopularityHighlight? = if otherMembers >= 2, likes >= otherMembers {
                    .allLiked
                } else if likes >= threshold {
                    .popular
                } else {
                    nil
                }
                #expect(
                    Probability.highlight(likeCount: likes, memberCount: memberCount) == expected,
                    "n' = \(otherMembers)・いいね \(likes)"
                )
            }
        }
    }
}
