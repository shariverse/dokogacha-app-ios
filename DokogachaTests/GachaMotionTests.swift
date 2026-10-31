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
        // 刻みの時刻ちょうどに 90° の倍数で止まる
        for step in 1..<GachaMotion.leverStepCount {
            let tick = GachaTimeline.tickInterval * Double(step)
            #expect(abs(GachaMotion.leverAngle(at: tick) - GachaMotion.leverStepDegrees * Double(step)) < 1e-9)
        }
        // 止まった直後に少し行き過ぎてから戻る。行き過ぎ（止まった角度を超えた分）は 4.5° 未満
        var maxOvershoot = 0.0
        for step in 1..<GachaMotion.leverStepCount {
            let clicked = GachaMotion.leverStepDegrees * Double(step)
            for frame in 0..<100 {
                let time = GachaTimeline.tickInterval * (Double(step) + Double(frame) / 100 * GachaMotion.leverSettleFraction)
                maxOvershoot = max(maxOvershoot, GachaMotion.leverAngle(at: time) - clicked)
            }
        }
        #expect(maxOvershoot > 2)
        #expect(maxOvershoot < 4.5)
    }

    /// ドームの揺れは 0.4 秒で 0 → −4° → 4° → −3° → 3° → 0 を通る。抽選の結果が遅いときは回転中のまま揺れ続け、落ち始めから収めて 0 にする
    @Test
    func domeShakesUntilDropStarts() {
        let segment = DGMotion.shake.duration / Double(GachaTimeline.shakeAngles.count)
        for (offset, angle) in GachaTimeline.shakeAngles.enumerated() {
            #expect(abs(GachaMotion.domeAngle(spinTime: segment * Double(offset + 1) - 1e-9, dropTime: nil) - angle) < 1e-3)
        }
        #expect(GachaMotion.domeAngle(spinTime: 0, dropTime: nil) == 0)
        // 1.6 秒を過ぎても、落ち始めるまでは揺れ続ける（通信が遅いとき）
        let late = GachaTimeline.spinDuration + segment
        #expect(abs(GachaMotion.domeAngle(spinTime: late, dropTime: nil) - GachaTimeline.shakeAngles[0]) < 1e-3)
        // 落ち始めから収めて 0 にする
        let settling = GachaMotion.domeAngle(spinTime: late + 0.1, dropTime: 0.1)
        #expect(abs(settling) < abs(GachaMotion.domeAngle(spinTime: late + 0.1, dropTime: nil)) + 1e-9)
        #expect(GachaMotion.domeAngle(spinTime: late + GachaMotion.settleDuration, dropTime: GachaMotion.settleDuration) == 0)
    }

    /// ドームのカプセルは回転中にかき混ぜ（上にだけ跳ねる）、通信が遅くても落ち始めるまで続け、落ち始めから置き場所に収める
    @Test
    func capsulesTumbleUntilDropStarts() {
        #expect(GachaMotion.tumbleAmount(spinTime: 0, dropTime: nil) == 0)
        #expect(GachaMotion.tumbleAmount(spinTime: 0.7, dropTime: nil) == 1)
        #expect(GachaMotion.tumbleAmount(spinTime: 3, dropTime: nil) == 1)
        #expect(GachaMotion.tumbleAmount(spinTime: 3, dropTime: GachaMotion.settleDuration) == 0)
        for index in 0..<DGGachaCapsuleLayout.maxVisibleCount {
            #expect(GachaMotion.tumble(index: index, spinTime: 0, dropTime: nil) == .rest)
            let moving = GachaMotion.tumble(index: index, spinTime: 0.7, dropTime: nil)
            #expect(moving.offset.height <= 0)
            #expect(abs(moving.offset.width) <= GachaMotion.tumbleSway.base + GachaMotion.tumbleSway.spread)
            #expect(-moving.offset.height <= GachaMotion.tumbleHop.base + GachaMotion.tumbleHop.spread)
            // 収めた後はずれが無く、角度は止まったまま
            let spinAtDrop = GachaTimeline.spinDuration
            let settled = GachaMotion.tumble(index: index, spinTime: spinAtDrop + 1, dropTime: 1)
            #expect(settled.offset == .zero)
            #expect(abs(settled.turnDegrees - GachaMotion.tumble(index: index, spinTime: spinAtDrop + 2, dropTime: 2).turnDegrees) < 1e-9)
        }
        // 番号ごとに動きをずらす（すべてが同じ向きに動かない）
        let offsets = (0..<6).map { GachaMotion.tumble(index: $0, spinTime: 0.7, dropTime: nil).offset.width }
        #expect(Set(offsets.map { $0 > 0 }).count == 2)
    }

    /// 転がる角度は巻き戻らない（向きが変わらず、速さは転がる速さの上限を超えない）
    @Test(arguments: [0, 1, 7])
    func tumbleTurnNeverUnwinds(index: Int) {
        let maxSpeed = GachaMotion.tumbleSpin.base + GachaMotion.tumbleSpin.spread
        let step = 1.0 / 120
        let spinAtDrop = GachaTimeline.spinDuration
        var previous = 0.0
        for frame in 1...Int((spinAtDrop + 0.6) / step) {
            let time = Double(frame) * step
            let dropTime = time > spinAtDrop ? time - spinAtDrop : nil
            let angle = GachaMotion.tumble(index: index, spinTime: time, dropTime: dropTime).turnDegrees
            let delta = angle - previous
            #expect(abs(delta) <= maxSpeed * step + 1e-6)
            #expect(delta * (index.isMultiple(of: 2) ? 1 : -1) >= -1e-9)
            previous = angle
        }
    }

    /// 「視差効果を減らす」では筐体を動かさない（傾き・回転・ずれ・拡大が無い）
    @Test
    func reducedMotionPoseIsStill() {
        let pose = GachaMotion.machinePose(
            times: GachaMotion.StageTimes(spin: 0.8, drop: 0.3, open: 0.2), capsuleCount: 3, winnerIndex: 1, reduceMotion: true
        )
        #expect(pose == DGGachaMachine.Pose())
        let moving = GachaMotion.machinePose(
            times: GachaMotion.StageTimes(spin: 0.9), capsuleCount: 3, winnerIndex: 1, reduceMotion: false
        )
        #expect(moving.domeRotationDegrees != 0)
        #expect(moving.capsuleTransforms.count == 3)
    }

    /// 落ち始めの前後で、当選のカプセルの形（位置・角度・大きさ）が跳ばない（かき混ぜていた形から続けて抜く）。
    /// 1.6 秒で落ち始めるときも、通信が遅くて後から落ち始めるときも確かめる
    @Test(arguments: [GachaTimeline.spinDuration, 2.3])
    func winnerDoesNotJumpWhenDropStarts(spinAtDrop: Double) {
        for winner in 0..<10 {
            let before = Self.winnerTransform(GachaMotion.StageTimes(spin: spinAtDrop), winner: winner)
            let after = Self.winnerTransform(GachaMotion.StageTimes(spin: spinAtDrop + 1e-6, drop: 1e-6), winner: winner)
            #expect(abs(after.offset.width - before.offset.width) < 0.01, "\(winner) の横")
            #expect(abs(after.offset.height - before.offset.height) < 0.01, "\(winner) の縦")
            #expect(abs(after.turnDegrees - before.turnDegrees) < 0.01, "\(winner) の角度")
            #expect(abs(after.scale - before.scale) < 1e-3, "\(winner) の大きさ")
            #expect(abs(after.opacity - before.opacity) < 1e-3, "\(winner) の不透明度")
        }
    }

    /// 10 個のカプセルのうち、`winner` 番目を当選にしたときの、そのカプセルの形（番号が 10 未満なら、置き場所はカプセルの数によらない）
    private static func winnerTransform(_ times: GachaMotion.StageTimes, winner: Int) -> DGGachaMachine.CapsuleTransform {
        let pose = GachaMotion.machinePose(times: times, capsuleCount: 10, winnerIndex: winner, reduceMotion: false)
        return pose.capsuleTransforms[winner] ?? .rest
    }

    /// 落ち始めたら、当選のカプセルを手前に描き、抜けきったときにはドームの底の抜け口に着いて消えている
    @Test
    func winnerIsDrawnInFrontWhileExiting() throws {
        let pose = GachaMotion.machinePose(
            times: GachaMotion.StageTimes(spin: GachaTimeline.spinDuration + 0.1, drop: 0.1),
            capsuleCount: 3,
            winnerIndex: 2,
            reduceMotion: false
        )
        #expect(pose.frontCapsuleIndex == 2)
        let center = try #require(DGGachaCapsuleLayout.center(at: 2))
        let exited = Self.winnerTransform(
            GachaMotion.StageTimes(spin: GachaTimeline.spinDuration + GachaTimeline.exitDuration, drop: GachaTimeline.exitDuration),
            winner: 2
        )
        #expect(abs(center.x + exited.offset.width - GachaMotion.exitPoint.x) < 1e-6)
        #expect(abs(center.y + exited.offset.height - GachaMotion.exitPoint.y) < 1e-6)
        #expect(exited.opacity == 0)
        let spinning = GachaMotion.machinePose(
            times: GachaMotion.StageTimes(spin: 0.5), capsuleCount: 3, winnerIndex: 2, reduceMotion: false
        )
        #expect(spinning.frontCapsuleIndex == nil)
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
