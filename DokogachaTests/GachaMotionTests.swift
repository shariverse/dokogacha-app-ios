//
//  GachaMotionTests.swift
//  DokogachaTests
//

import CoreGraphics
@testable import Dokogacha
import Foundation
import Testing

/// S-13 の筐体の動き（04 の §5 の `turn`・`shake`・`tumble`・`exit`・`drop`。Issue #178）
struct GachaMotionTests {
    /// レバーは 0.2 秒ごとに 90° ずつ回り、刻みの触覚と同じ時刻にちょうど刻みの角度で止まる。回し終えたら 720°
    @Test
    func leverClicksEveryTick() {
        #expect(GachaMotion.leverStepCount == 8)
        #expect(GachaMotion.leverStepDegrees == 90)
        #expect(GachaMotion.leverAngle(at: 0) == 0)
        for step in 1..<GachaMotion.leverStepCount {
            let tick = GachaTimeline.tickInterval * Double(step)
            // 刻みの直前は 90° の倍数のすぐ手前まで来ている
            let before = GachaMotion.leverAngle(at: tick - 1e-6)
            #expect(abs(before - GachaMotion.leverStepDegrees * Double(step)) < 0.01)
        }
        #expect(GachaMotion.leverAngle(at: GachaTimeline.spinDuration) == GachaTimeline.turnDegrees)
        // 刻みの後は少し行き過ぎてから戻る
        let overshoot = GachaMotion.leverAngle(at: GachaTimeline.tickInterval + 0.02)
        #expect(overshoot > GachaMotion.leverStepDegrees)
        // 角度はほぼ減らない（行き過ぎから戻る分だけ）
        var previous = 0.0
        for frame in 0...160 {
            let angle = GachaMotion.leverAngle(at: Double(frame) / 100)
            #expect(angle >= previous - GachaMotion.leverOvershootDegrees)
            previous = angle
        }
    }

    /// ドームの揺れは 0.4 秒で 0 → −4° → 4° → −3° → 3° → 0 を通り、回転中の外では 0
    @Test
    func domeShakesDuringSpin() {
        let segment = DGMotion.shake.duration / Double(GachaTimeline.shakeAngles.count)
        for (offset, angle) in GachaTimeline.shakeAngles.enumerated() {
            #expect(abs(GachaMotion.domeAngle(at: segment * Double(offset + 1) - 1e-9) - angle) < 1e-3)
        }
        #expect(GachaMotion.domeAngle(at: 0) == 0)
        #expect(GachaMotion.domeAngle(at: GachaTimeline.spinDuration) == 0)
    }

    /// ドームのカプセルは回転中だけかき混ぜ（上にだけ跳ねる）、回し始めと回し終えでは置き場所のまま
    @Test
    func capsulesTumbleOnlyWhileSpinning() {
        #expect(GachaMotion.tumbleAmount(at: 0) == 0)
        #expect(GachaMotion.tumbleAmount(at: GachaTimeline.spinDuration) == 0)
        #expect(GachaMotion.tumbleAmount(at: GachaTimeline.spinDuration / 2) == 1)
        for index in 0..<DGGachaCapsuleLayout.maxVisibleCount {
            #expect(GachaMotion.tumble(index: index, at: 0) == .rest)
            #expect(GachaMotion.tumble(index: index, at: GachaTimeline.spinDuration) == .rest)
            let moving = GachaMotion.tumble(index: index, at: 0.7)
            #expect(moving.offset.height <= 0)
            #expect(abs(moving.offset.width) <= GachaMotion.tumbleSway.base + GachaMotion.tumbleSway.spread)
            #expect(-moving.offset.height <= GachaMotion.tumbleHop.base + GachaMotion.tumbleHop.spread)
        }
        // 番号ごとに動きをずらす（すべてが同じ向きに動かない）
        let offsets = (0..<6).map { GachaMotion.tumble(index: $0, at: 0.7).offset.width }
        #expect(Set(offsets.map { $0 > 0 }).count == 2)
    }

    /// 当選のカプセルは、置き場所からドームの底の抜け口へ吸い込まれて消える
    @Test
    func winnerExitsThroughDomeBottom() throws {
        let center = try #require(DGGachaCapsuleLayout.center(at: 1))
        #expect(GachaMotion.exit(from: center, at: 0) == .rest)
        let done = GachaMotion.exit(from: center, at: GachaTimeline.exitDuration)
        #expect(abs(center.x + done.offset.width - GachaMotion.exitPoint.x) < 1e-9)
        #expect(abs(center.y + done.offset.height - GachaMotion.exitPoint.y) < 1e-9)
        #expect(done.opacity == 0)
        #expect(done.scale == GachaMotion.exitScale)
        #expect(DGGachaCapsuleLayout.center(at: DGGachaCapsuleLayout.maxVisibleCount) == nil)
    }

    /// 取り出し口のカプセルは、抜けるまで見えず、底に当たった瞬間につぶれ、落ち終えたら置き場所の形に戻る
    @Test
    func dispensedCapsuleSquashesOnLanding() {
        let hidden = GachaMotion.dispensed(at: GachaTimeline.exitDuration)
        #expect(hidden.opacity == 0)
        #expect(hidden.offsetY == GachaTimeline.DropKeyframes.startOffset)
        let landed = GachaMotion.dispensed(at: GachaTimeline.landingDelay + 1e-6)
        #expect(abs(landed.offsetY - GachaTimeline.DropKeyframes.landingOffset) < 0.01)
        #expect(landed.opacity == 1)
        #expect(landed.squash.height < 1)
        #expect(landed.squash.width > 1)
        let rest = GachaMotion.dispensed(at: GachaTimeline.exitDuration + DGMotion.drop.duration + 0.001)
        #expect(rest == GachaMotion.DispensedPose())
    }
}
