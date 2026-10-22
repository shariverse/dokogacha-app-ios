//
//  GachaMachineStage.swift
//  Dokogacha
//

import SwiftUI

/// S-13 の筐体（`DGGachaMachine`）に、演出の段階に合わせた動きを付ける（04 の §5 の `shake`・`turn`・`drop`・`pulse`・`open`）。
///
/// - `shake`（ドーム）: 0 → −4° → 4° → −3° → 3° → 0 の 1 回（0.4 秒）を、回転中だけ繰り返す（`KeyframeAnimator` の `repeating`。
///   行って戻るだけの `repeatCount(autoreverses:)` では作れない）。回転中の 1.6 秒でちょうど 4 回
/// - `turn`（レバーのバー）: 回転中に入ったら 720° 回す（1.6 秒）
/// - `drop`（出てくるカプセル）: 落ち始めたら、上 −90 から落ちて +6 → −8 → 0 と跳ねる（0.7 秒。不透明になるのは底に当たるまで）
/// - `pulse`（出てきたカプセル）: 取り出し口で押せる間だけ 1.0 ↔ 1.08 を繰り返す（1.2 秒周期。押せるのは落ち始めて 0.8 秒後から）
/// - `open`（カプセル）: 開けたら 1.6 倍に拡大しながら消える（0.5 秒）
///
/// 回転中でなくなったら（通信エラーで止めたときを含む）、揺れとレバーの角度は 0 に戻す。
/// 「視差効果を減らす」がオンのときは揺れ・回転・落下・拡大縮小をせず、カプセルの出入りをフェード 0.2 秒だけにする（04 の §5）。
struct GachaMachineStage: View {
    /// 落ちるカプセルの値（縦のずれ・不透明度）
    private struct DropValue {
        var offset: Double = 0
        var opacity: Double = 1
    }

    /// 画面の状態
    let model: GachaModel
    /// 「視差効果を減らす」か
    let reduceMotion: Bool

    /// レバーのバーの角度（回転中に入ったら 720 にする）
    @State private var leverDegrees: Double = 0
    /// 落下の演出の回数（変わるたびに `drop` を始める）
    @State private var dropCount = 0
    /// 取り出し口にカプセルを出しているか（視差効果を減らすときはフェードで出し入れする）
    @State private var showsCapsule = false
    /// カプセルを開けているか（`open`）
    @State private var isOpening = false

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, repeating: isShaking) { domeDegrees in
            KeyframeAnimator(initialValue: DropValue(), trigger: dropCount) { drop in
                KeyframeAnimator(initialValue: 1.0, repeating: isPulsing) { pulse in
                    machine(domeDegrees: domeDegrees, drop: drop, pulse: pulse)
                } keyframes: { _ in
                    pulseKeyframes
                }
            } keyframes: { _ in
                dropKeyframes
            }
        } keyframes: { _ in
            shakeKeyframes
        }
        .onAppear {
            // 見終えた抽選で開いたときは、初めから取り出し口にカプセルがある
            showsCapsule = model.phase.showsCapsule
        }
        .onChange(of: model.phase) { oldPhase, phase in
            update(from: oldPhase, to: phase)
        }
    }

    /// ドームを揺らしているか（回転中だけ）
    private var isShaking: Bool {
        model.phase == .spinning && !reduceMotion
    }

    /// 出てきたカプセルを拡大縮小しているか（押せる間だけ）
    private var isPulsing: Bool {
        model.phase == .dispensed && !reduceMotion
    }

    /// いまの動きの値を入れた筐体
    private func machine(domeDegrees: Double, drop: DropValue, pulse: Double) -> DGGachaMachine {
        let isSpinning = model.phase == .spinning
        let openScale = isOpening && !reduceMotion ? GachaTimeline.openScale : 1
        return DGGachaMachine(
            capsuleColors: model.capsuleColorIndexes.map(Color.dgCapsule(at:)),
            dispensedColor: showsCapsule ? Color.dgCapsule(at: model.winnerColorIndex) : nil,
            isLeverEnabled: model.canTurnLever,
            isCapsuleEnabled: model.isCapsuleEnabled,
            pose: DGGachaMachine.Pose(
                domeRotationDegrees: isSpinning ? domeDegrees : 0,
                leverRotationDegrees: isSpinning ? leverDegrees : 0,
                dispensedOffsetY: drop.offset,
                dispensedScale: pulse * openScale,
                dispensedOpacity: isOpening ? 0 : drop.opacity
            ),
            onTurnLever: { model.leverTapped() },
            onOpenCapsule: { model.capsuleTapped() }
        )
    }

    /// 段階が変わったときに、動きを始める
    private func update(from oldPhase: GachaPhase, to phase: GachaPhase) {
        if phase == .spinning, !reduceMotion {
            leverDegrees = 0
            withAnimation(DGMotion.turn.animation) {
                leverDegrees = GachaTimeline.turnDegrees
            }
        } else if oldPhase == .spinning {
            leverDegrees = 0
        }
        if phase == .dropping, !reduceMotion {
            dropCount += 1
        }
        if reduceMotion {
            withAnimation(DGMotion.reducedFade) {
                showsCapsule = phase.showsCapsule
                isOpening = phase == .opening || phase == .opened
            }
        } else {
            showsCapsule = phase.showsCapsule
            if phase == .opening {
                withAnimation(DGMotion.open.animation) {
                    isOpening = true
                }
            } else if !phase.showsCapsule {
                isOpening = false
            }
        }
    }

    // MARK: - キーフレーム

    /// ドームの揺れ 1 回分（0.4 秒を 5 つに分け、それぞれ easeInOut。プロトタイプの `dgShake`）
    private var shakeKeyframes: some Keyframes<Double> {
        let segment = DGMotion.shake.duration / Double(GachaTimeline.shakeAngles.count)
        let angles = GachaTimeline.shakeAngles
        return KeyframeTrack {
            LinearKeyframe(angles[0], duration: segment, timingCurve: .easeInOut)
            LinearKeyframe(angles[1], duration: segment, timingCurve: .easeInOut)
            LinearKeyframe(angles[2], duration: segment, timingCurve: .easeInOut)
            LinearKeyframe(angles[3], duration: segment, timingCurve: .easeInOut)
            LinearKeyframe(angles[4], duration: segment, timingCurve: .easeInOut)
        }
    }

    /// 落ちるカプセルが底に当たるまでの時間
    private static let landingDuration = DGMotion.drop.duration * GachaTimeline.DropKeyframes.landingFraction
    /// 底から跳ね返りの頂点までの時間
    private static let bounceDuration = DGMotion.drop.duration
        * (GachaTimeline.DropKeyframes.bounceFraction - GachaTimeline.DropKeyframes.landingFraction)
    /// 跳ね返りの頂点から止まるまでの時間
    private static let settleDuration = DGMotion.drop.duration * (1 - GachaTimeline.DropKeyframes.bounceFraction)

    /// 落ちるカプセル（プロトタイプの `dgDrop`。区間ごとに easeOut）
    @KeyframesBuilder<DropValue> private var dropKeyframes: some Keyframes<DropValue> {
        KeyframeTrack(\.offset) {
            MoveKeyframe(GachaTimeline.DropKeyframes.startOffset)
            LinearKeyframe(GachaTimeline.DropKeyframes.landingOffset, duration: Self.landingDuration, timingCurve: .easeOut)
            LinearKeyframe(GachaTimeline.DropKeyframes.bounceOffset, duration: Self.bounceDuration, timingCurve: .easeOut)
            LinearKeyframe(0, duration: Self.settleDuration, timingCurve: .easeOut)
        }
        KeyframeTrack(\.opacity) {
            MoveKeyframe(0)
            LinearKeyframe(1, duration: Self.landingDuration, timingCurve: .easeOut)
        }
    }

    /// 出てきたカプセルの拡大縮小 1 周期（1.2 秒を行きと帰りに分け、それぞれ easeInOut）
    private var pulseKeyframes: some Keyframes<Double> {
        let half = DGMotion.pulse.duration / 2
        return KeyframeTrack {
            LinearKeyframe(GachaTimeline.pulseScale, duration: half, timingCurve: .easeInOut)
            LinearKeyframe(1, duration: half, timingCurve: .easeInOut)
        }
    }
}
