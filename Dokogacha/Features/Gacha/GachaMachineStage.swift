//
//  GachaMachineStage.swift
//  Dokogacha
//

import SwiftUI

/// S-13 の筐体（`DGGachaMachine`）に、演出の段階に合わせた動きを付ける（04 の §5 の `shake`・`turn`・`tumble`・`exit`・`drop`・`open`。Issue #178）。
///
/// 段階が変わった時刻を覚え、`TimelineView` の時刻から `GachaMotion` の形を読んで描く（動いている間だけ時刻を進める）。
/// - 回転中（1.6 秒）: ドームが揺れ（`shake`）、レバーが 0.2 秒ごとに 90° ずつカチッと回り（`turn`。刻みの触覚と同じ時刻）、
///   ドームの中のカプセルがかき混ぜられて跳ねる（`tumble`。回し始めに強め、終わりに収める）
/// - 落ち始め: 当選のカプセルがドームの底へ吸い込まれて消え（`exit` 0.35 秒）、取り出し口の上から落ちて跳ね、
///   底に当たった瞬間につぶれ、跳ね返りで少し転がって戻る（`drop` 0.7 秒）
/// - 開ける: 1.6 倍に拡大しながら消える（`open` 0.5 秒）
///
/// 回転中でなくなったら（通信エラーで止めたときを含む）、待機の形に戻す。
/// 「視差効果を減らす」がオンのときは揺れ・回転・かき混ぜ・落下・拡大をせず、カプセルの出入りをフェード 0.2 秒だけにする（04 の §5）。
struct GachaMachineStage: View {
    /// 画面の状態
    let model: GachaModel
    /// 「視差効果を減らす」か
    let reduceMotion: Bool

    /// 回し始めた時刻（回転中だけ）
    @State private var spinStart: Date?
    /// 落ち始めた時刻（落ちている途中から後）
    @State private var dropStart: Date?
    /// 開け始めた時刻（開けている途中から後）
    @State private var openStart: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isMoving)) { context in
            machine(at: context.date)
        }
        .onAppear {
            // 見終えた抽選で開いたときは、初めから取り出し口にカプセルがあることがある
            start(model.phase, at: .now)
        }
        .onChange(of: model.phase) { _, phase in
            start(phase, at: .now)
        }
    }

    /// 時刻を進めて描き直しているか（演出の途中だけ）
    private var isMoving: Bool {
        model.phase.isAnimating
    }

    /// 段階に入った時刻を覚える（待機に戻ったら忘れる）
    private func start(_ phase: GachaPhase, at date: Date) {
        switch phase {
        case .idle:
            spinStart = nil
            dropStart = nil
            openStart = nil
        case .spinning:
            spinStart = date
            dropStart = nil
            openStart = nil
        case .dropping:
            spinStart = nil
            dropStart = dropStart ?? date
        case .opening, .opened:
            spinStart = nil
            // 落とさずに開けるところから始めたとき（見終えた抽選）は、落ち終えたことにする
            dropStart = dropStart ?? .distantPast
            openStart = openStart ?? date
        }
    }

    /// 時刻 `date` の筐体
    private func machine(at date: Date) -> DGGachaMachine {
        let spinTime = spinStart.map { date.timeIntervalSince($0) }
        let dropTime = dropStart.map { date.timeIntervalSince($0) }
        let openTime = openStart.map { date.timeIntervalSince($0) }
        return DGGachaMachine(
            capsuleColors: model.capsuleColorIndexes.map(Color.dgCapsule(at:)),
            dispensedColor: dropTime == nil ? nil : Color.dgCapsule(at: model.winnerColorIndex),
            isLeverEnabled: model.canTurnLever,
            pose: pose(spinTime: spinTime, dropTime: dropTime, openTime: openTime),
            onTurnLever: { model.leverTapped() }
        )
    }

    /// 時刻から求めた動かす値
    private func pose(spinTime: Double?, dropTime: Double?, openTime: Double?) -> DGGachaMachine.Pose {
        var pose = DGGachaMachine.Pose()
        if reduceMotion {
            // 動かさず、出入りだけをフェードにする
            if let dropTime {
                pose.dispensedOpacity = RevealCurve.progress(dropTime, from: 0, duration: DGMotion.reducedFadeDuration)
                if let winner = model.winnerCapsuleIndex {
                    pose.capsuleTransforms[winner] = DGGachaMachine.CapsuleTransform(opacity: 1 - pose.dispensedOpacity)
                }
            }
            if let openTime {
                pose.dispensedOpacity = 1 - RevealCurve.progress(openTime, from: 0, duration: DGMotion.reducedFadeDuration)
            }
            return pose
        }
        if let spinTime {
            pose.domeRotationDegrees = GachaMotion.domeAngle(at: spinTime)
            pose.leverRotationDegrees = GachaMotion.leverAngle(at: spinTime)
            for index in model.capsuleColorIndexes.indices.prefix(DGGachaCapsuleLayout.maxVisibleCount) {
                pose.capsuleTransforms[index] = GachaMotion.tumble(index: index, at: spinTime)
            }
        }
        if let dropTime {
            if let winner = model.winnerCapsuleIndex, let center = DGGachaCapsuleLayout.center(at: winner) {
                pose.capsuleTransforms[winner] = GachaMotion.exit(from: center, at: dropTime)
            }
            let dispensed = GachaMotion.dispensed(at: dropTime)
            pose.dispensedOffsetY = dispensed.offsetY
            pose.dispensedOpacity = dispensed.opacity
            pose.dispensedSquash = dispensed.squash
            pose.dispensedRotationDegrees = dispensed.rotationDegrees
        }
        if let openTime {
            let open = RevealCurve.easeIn(RevealCurve.progress(openTime, from: 0, duration: DGMotion.open.duration))
            pose.dispensedScale = RevealCurve.mix(1, GachaTimeline.openScale, open)
            pose.dispensedOpacity = 1 - open
        }
        return pose
    }
}
