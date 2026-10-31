//
//  ResultRevealTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-14 で行き先きっぷを出す演出の案（Issue #158）の予定・動き・切り替え
struct ResultRevealTests {
    /// 案の演出（今の演出を除く）
    nonisolated static let revealStyles: [ResultRevealStyle] = [.capsule, .flap, .issue]

    /// 起動引数 `-result-animation <案>` で案を選ぶ（Debug ビルドのテストで読める。知らない値・無いときは nil）
    @Test
    func launchArgumentSelectsStyle() {
        func style(_ arguments: [String]) -> ResultRevealStyle? {
            LaunchContext(arguments: ["Dokogacha"] + arguments, environment: [:]).resultRevealStyle
        }
        #expect(style(["-result-animation", "capsule"]) == .capsule)
        #expect(style(["-screenshot-demo", "-result-animation", "flap"]) == .flap)
        #expect(style(["-uiTesting", "-result-animation", "issue"]) == .issue)
        #expect(style(["-result-animation", "pop"]) == .pop)
        #expect(style(["-result-animation", "unknown"]) == nil)
        #expect(style(["-result-animation"]) == nil)
        #expect(style([]) == nil)
    }

    /// 予定は時刻の順で、決まる → 終わる → 止まるの順に並ぶ。「決まった」の触覚は、見出しを出すより後にならない。
    /// 刻みの触覚は、動きのある案だけで鳴らす
    @Test(arguments: Self.revealStyles, [false, true])
    func planOrdersPhases(style: ResultRevealStyle, reduceMotion: Bool) {
        let plan = ResultRevealStage.plan(for: style, reduceMotion: reduceMotion)
        #expect(plan.events.map(\.time) == plan.events.map(\.time).sorted())
        #expect(plan.decidedAt > 0)
        #expect(plan.decidedAt < plan.settledAt)
        #expect(plan.settledAt <= plan.duration)
        #expect(plan.decidedCueAt != nil)
        #expect((plan.decidedCueAt ?? .infinity) <= plan.decidedAt)
        let tickTimes = plan.events.compactMap { event -> Double? in
            if case .cue(.tick) = event.kind {
                return event.time
            }
            return nil
        }
        // A・B の刻みは「決まった」より前だけ（決まった後は静かにする）。C は名前の後の残りも押し出すので、決まった後も刻みが続く
        if style != .issue {
            #expect(tickTimes.allSatisfy { $0 < (plan.decidedCueAt ?? 0) })
        }
        // 視差効果を減らすときは刻みを鳴らさない（動きが無いので）
        if reduceMotion {
            #expect(tickTimes.isEmpty)
        }
    }

    /// 演出の長さ（案ごとの「決まる瞬間」と「終わる」の目安。比較の表と同じ値）
    @Test
    func planDurationsMatchComparison() {
        func times(_ style: ResultRevealStyle) -> (Double, Double) {
            let plan = ResultRevealStage.plan(for: style, reduceMotion: false)
            return ((plan.decidedCueAt ?? 0), plan.settledAt)
        }
        #expect(abs(times(.capsule).0 - 1.38) < 1e-9)
        #expect(abs(times(.capsule).1 - 2.48) < 1e-9)
        #expect(abs(times(.flap).0 - 1.98) < 1e-9)
        #expect(abs(times(.flap).1 - 3.61) < 1e-9)
        #expect(abs(times(.issue).0 - 1.82) < 1e-9)
        #expect(abs(times(.issue).1 - 3.37) < 1e-9)
    }

    /// 演出の後は、どの案も飾りの無いきっぷだけの形になる（今の演出の最後と同じ見た目）
    @Test(arguments: [false, true])
    func posesEndWithPlainTicket(reduceMotion: Bool) {
        let capsuleEnd = CapsuleBurstTimeline.plan(reduceMotion: reduceMotion).duration + 0.01
        let capsule = CapsuleBurstTimeline.pose(at: capsuleEnd, reduceMotion: reduceMotion)
        #expect(capsule.capsuleOpacity == 0)
        #expect(!capsule.showsHalves)
        #expect(capsule.confettiTime == nil)
        #expect(capsule.ticketScale == 1 && capsule.ticketTurn == 0 && capsule.ticketOpacity == 1)
        #expect(capsule.stampProgress == 1)

        let flapEnd = FlapBoardTimeline.plan(reduceMotion: reduceMotion).duration + 0.01
        let flap = FlapBoardTimeline.pose(at: flapEnd, reduceMotion: reduceMotion)
        #expect(flap.boardOpacity == 0)
        #expect(flap.ticketAngle == 0 && flap.ticketOpacity == 1)
        #expect(flap.stampProgress == 1)

        let issueEnd = TicketIssueTimeline.plan(reduceMotion: reduceMotion).duration + 0.01
        let issue = TicketIssueTimeline.pose(at: issueEnd, height: 320, reduceMotion: reduceMotion)
        #expect(issue.ticketOffset == 0 && issue.ticketOpacity == 1)
        #expect(issue.slotOpacity == 0)
        #expect(!issue.masksBelowSlot)
        #expect(issue.stampProgress == 1)
    }

    /// 演出の始めは、どの案も行き先を見せない（きっぷは隠れ、ハンコは押していない）
    @Test
    func posesStartHidingDestination() {
        let capsule = CapsuleBurstTimeline.pose(at: 0, reduceMotion: false)
        #expect(capsule.capsuleOpacity == 1)
        #expect(capsule.ticketOpacity == 0)
        #expect(capsule.stampProgress == 0)

        let flap = FlapBoardTimeline.pose(at: 0, reduceMotion: false)
        #expect(flap.boardOpacity == 1)
        #expect(flap.index == 0)
        #expect(flap.ticketOpacity == 0)

        let issue = TicketIssueTimeline.pose(at: 0, height: 320, reduceMotion: false)
        #expect(issue.ticketOffset == 320)
        #expect(issue.masksBelowSlot)
        #expect(issue.stampProgress == 0)
    }

    /// 案 A: 割れる直前にいちばん大きく揺れ、割れる瞬間に殻・きっぷ・紙吹雪を出す
    @Test
    func capsuleBurstsAtDecidedMoment() {
        let before = CapsuleBurstTimeline.pose(at: CapsuleBurstTimeline.burstAt - 0.001, reduceMotion: false)
        #expect(before.capsuleOpacity == 1)
        #expect(before.capsuleScale.height < 1)
        let after = CapsuleBurstTimeline.pose(at: CapsuleBurstTimeline.burstAt + 0.05, reduceMotion: false)
        #expect(after.capsuleOpacity == 0)
        #expect(after.showsHalves)
        #expect(after.confettiTime != nil)
        #expect(after.ticketOpacity > 0)
        // 揺れの角度は区間の行き先を通り、揺れの外では 0
        #expect(CapsuleBurstTimeline.wobbleAngle(at: 0) == 0)
        let firstPeak = CapsuleBurstTimeline.wobbleStart + CapsuleBurstTimeline.wobbleSegment
        #expect(abs(CapsuleBurstTimeline.wobbleAngle(at: firstPeak - 1e-9) - CapsuleBurstTimeline.wobbleAngles[0]) < 1e-3)
        #expect(CapsuleBurstTimeline.wobbleAngle(at: CapsuleBurstTimeline.wobbleEnd) == 0)
    }

    /// 案 B: めくる文字は「？？？」で始まり、当選の名前で終わり、同じ文字が続かない
    @Test(arguments: [
        ["サンシャイン水族館", "明治神宮", "代々木公園"],
        ["サンシャイン水族館", "明治神宮"],
        ["サンシャイン水族館"],
        []
    ])
    func flapTextsEndWithWinner(names: [String]) {
        let texts = FlapBoardTimeline.texts(names: names, winner: "サンシャイン水族館")
        #expect(texts.count == FlapBoardTimeline.flipCount + 1)
        #expect(texts.first == FlapBoardTimeline.undecided)
        #expect(texts.last == "サンシャイン水族館")
        #expect(!texts.dropLast().contains("サンシャイン水族館"))
        #expect(zip(texts, texts.dropFirst()).allSatisfy { $0 != $1 })
    }

    /// 案 B: めくりは速く回ってから遅くなり、止まった瞬間に当選の名前になる
    @Test
    func flapSlowsDownAndStopsOnWinner() {
        let durations = FlapBoardTimeline.flipDurations
        #expect(durations.last == durations.max())
        let tail = Array(durations.suffix(5))
        #expect(tail == tail.sorted())
        let stopped = FlapBoardTimeline.pose(at: FlapBoardTimeline.stopAt + 0.01, reduceMotion: false)
        #expect(stopped.index == FlapBoardTimeline.flipCount)
        #expect(stopped.flip == nil)
        #expect(stopped.isLit)
        let flipping = FlapBoardTimeline.pose(at: FlapBoardTimeline.flipStarts[3] + 0.01, reduceMotion: false)
        #expect(flipping.index == 3)
        #expect(flipping.flip != nil)
    }

    /// 案 C: 名前の手前で止め（溜め）、名前の段を出しきったら決まる。出ている長さは減らない
    @Test
    func issueHoldsBeforeDestination() {
        let height = 320.0
        let lead = TicketIssueTimeline.emergedLength(at: TicketIssueTimeline.leadEnd, height: height)
        #expect(abs(lead - TicketIssueTimeline.leadLength) < 1e-9)
        #expect(TicketIssueTimeline.emergedLength(at: TicketIssueTimeline.pushStart - 0.01, height: height) == lead)
        let pushed = TicketIssueTimeline.emergedLength(at: TicketIssueTimeline.pushEnd, height: height)
        #expect(abs(pushed - lead - TicketIssueTimeline.nameLength) < 1e-9)
        #expect(TicketIssueTimeline.emergedLength(at: TicketIssueTimeline.tailEnd, height: height) == height)
        var previous = 0.0
        for step in 0...400 {
            let length = TicketIssueTimeline.emergedLength(at: Double(step) / 100, height: height)
            #expect(length >= previous - 1e-9)
            previous = length
        }
        // 低いきっぷでも、名前の手前は高さの割合までで止める
        let short = TicketIssueTimeline.emergedLength(at: TicketIssueTimeline.leadEnd, height: 200)
        #expect(abs(short - 200 * TicketIssueTimeline.leadMaxFraction) < 1e-9)
    }

    /// 紙吹雪は毎回同じ散り方（乱数を使わない）で、6 色を使い、時間が来たら消える
    @Test
    func confettiIsDeterministic() {
        #expect(ConfettiPiece.all == (0..<ConfettiPiece.count).map(ConfettiPiece.make(index:)))
        #expect(Set(ConfettiPiece.all.map(\.colorIndex)).count == 6)
        #expect(ConfettiPiece.opacity(at: 0) == 1)
        #expect(ConfettiPiece.opacity(at: ConfettiPiece.lifetime) == 0)
        let piece = ConfettiPiece.make(index: 0)
        #expect(piece.offset(at: 0) == .zero)
    }

    /// ハンコの押し具合（2.2 倍・透明 → 0.92 倍 → 等倍。視差効果を減らすときは大きさを変えずにフェード）
    @Test
    func stampPressPoseFollowsMotionToken() {
        let start = DGStamp.pressPose(0, reduceMotion: false)
        #expect(abs(start.scale - 2.2) < 1e-9)
        #expect(start.opacity == 0)
        let pressed = DGStamp.pressPose(0.7, reduceMotion: false)
        #expect(abs(pressed.scale - 0.92) < 1e-9)
        #expect(pressed.opacity == 1)
        let end = DGStamp.pressPose(1, reduceMotion: false)
        #expect(end.scale == 1)
        #expect(end.opacity == 1)
        let reduced = DGStamp.pressPose(0.5, reduceMotion: true)
        #expect(reduced.scale == 1)
        #expect(reduced.opacity == 0.5)
    }

    /// 案の演出では、S-13 でカプセルが開いた瞬間を `.success` にしない（決まる瞬間の S-14 で鳴らす）
    @Test
    func capsuleOpenedFeedbackLeavesSuccessToReveal() {
        #expect(GachaCue.capsuleOpened.feedback(revealStyle: .pop) == .success)
        for style in Self.revealStyles {
            #expect(GachaCue.capsuleOpened.feedback(revealStyle: style) == .impact(weight: .medium))
        }
        #expect(GachaCue.leverPulled.feedback(revealStyle: .capsule) == .impact(weight: .heavy))
        #expect(ResultRevealCue.decided.feedback == .success)
    }
}
