//
//  GachaStageTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-13 の文言・合図の触覚・演出の時間（03 の S-13・04 の §5）
struct GachaStageTests {
    /// 段階とルームの状態から、03 の S-13 の表の文言を選ぶ
    @Test
    func captionFollowsScreenSpec() {
        func make(
            _ phase: GachaPhase, _ name: String? = nil, _ status: RoomStatus = .unlocked, reroll: Bool = false, count: Int = 3
        ) -> GachaCaption {
            GachaCaption.make(phase: phase, drawnByName: name, status: status, isReroll: reroll, capsuleCount: count)
        }
        #expect(make(.idle) == .ready(isReroll: false))
        #expect(make(.idle, reroll: true, count: 2) == .ready(isReroll: true))
        #expect(make(.idle, count: 0) == .noCandidates)
        #expect(make(.idle, nil, .open) == .locked)
        #expect(make(.spinning) == .spinning)
        #expect(make(.spinning, "はるか", .drawn) == .drawnByOther(name: "はるか"))
        for phase in [GachaPhase.dropping, .dispensed, .opening, .opened] {
            #expect(make(phase, "はるか", .drawn) == .dispensed)
        }
        #expect(String(localized: GachaCaption.ready(isReroll: false).title) == "レバーを回してね")
        #expect(String(localized: GachaCaption.ready(isReroll: false).subtitle) == "結果はメンバー全員の画面に同時に出ます")
        #expect(String(localized: GachaCaption.ready(isReroll: true).subtitle) == "引き直し（前回の当選は除外）")
        #expect(String(localized: GachaCaption.spinning.title) == "ガラガラ…")
        #expect(String(localized: GachaCaption.drawnByOther(name: "はるか").title) == "はるかさんが回しました！")
        #expect(String(localized: GachaCaption.drawnByOther(name: "はるか").subtitle) == "どこに決まるかな")
        #expect(String(localized: GachaCaption.dispensed.title) == "カプセルをタップ！")
        #expect(String(localized: GachaCaption.dispensed.subtitle) == "開けると行き先が決まります")
    }

    /// 合図ごとの触覚（03 の S-13）
    @Test
    func cueFeedbackFollowsScreenSpec() {
        #expect(GachaCue.leverPulled.feedback == .impact(weight: .heavy))
        #expect(GachaCue.spinTick.feedback == .impact(weight: .light))
        #expect(GachaCue.capsuleLanded.feedback == .impact(weight: .medium))
        #expect(GachaCue.capsuleOpened.feedback == .success)
    }

    /// 演出の時間（回転 1.6 秒・0.2 秒ごとの刻み 7 回・底に当たるのは落下 0.7 秒の 55%・押せるのは 0.8 秒後・開くのは 0.5 秒）
    @Test
    func timelineFollowsMotionTokens() {
        #expect(GachaTimeline.spinDuration == 1.6)
        #expect(DGMotion.shake.duration * Double(DGMotion.shake.repeatCount ?? 0) == GachaTimeline.spinDuration)
        #expect(GachaTimeline.tickCount == 7)
        #expect(abs(GachaTimeline.landingDelay - 0.385) < 1e-9)
        #expect(GachaTimeline.dispenseDelay == 0.8)
        #expect(GachaTimeline.openDuration == 0.5)
        #expect(GachaTimeline.shakeAngles == [-4, 4, -3, 3, 0])
    }

    /// 演出の途中か・取り出し口にカプセルを出しているか
    @Test
    func phaseFlags() {
        #expect([GachaPhase.idle, .spinning, .dropping, .dispensed, .opening, .opened].map(\.isAnimating)
            == [false, true, true, false, true, false])
        #expect([GachaPhase.idle, .spinning, .dropping, .dispensed, .opening, .opened].map(\.showsCapsule)
            == [false, false, true, true, true, true])
    }
}
