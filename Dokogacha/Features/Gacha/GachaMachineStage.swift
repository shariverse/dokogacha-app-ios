//
//  GachaMachineStage.swift
//  Dokogacha
//

import SwiftUI

/// S-13 の筐体（`DGGachaMachine`）に、演出の段階に合わせた動きを付ける（04 の §5 の `shake`・`turn`・`tumble`・`exit`・`drop`・`open`。Issue #178）。
///
/// 段階が変わった時刻を覚え、`TimelineView` の時刻から `GachaMotion.machinePose` の形を読んで描く（動いている間だけ時刻を進める）。
/// - 回転中: ドームが揺れ（`shake`）、レバーが 0.2 秒ごとに 90° ずつカチッと回り（`turn`。刻みの触覚と同じ時刻）、
///   ドームの中のカプセルがかき混ぜられて跳ねる（`tumble`）。抽選の結果が 1.6 秒より遅く返っても、揺れとかき混ぜは落ち始めるまで続ける
/// - 落ち始め: 揺れとかき混ぜを 0.35 秒で収め、当選のカプセルがドームの底へ吸い込まれて消え（`exit` 0.35 秒）、取り出し口の上から落ちて跳ね、
///   底に当たった瞬間につぶれ、跳ね返りで少し転がって戻る（`drop` 0.7 秒）
/// - 開ける: 1.6 倍に拡大しながら消える（`open` 0.5 秒）
///
/// 回転中でなくなったら（通信エラーで止めたときを含む）、待機の形に戻す。
/// 「視差効果を減らす」がオンのときは筐体を動かさず、取り出し口にもカプセルを出さない（Model は待たずに開け終えるので、
/// レバーを押したら S-14 へのフェード 0.2 秒だけで替わる。04 の §5「すべて即時切り替え」）。
struct GachaMachineStage: View {
    /// 画面の状態
    let model: GachaModel
    /// 「視差効果を減らす」か
    let reduceMotion: Bool

    /// 回し始めた時刻（回してから開け終えるまで）
    @State private var spinStart: Date?
    /// 落ち始めた時刻（落ちている途中から後）
    @State private var dropStart: Date?
    /// 開け始めた時刻（開けている途中から後）
    @State private var openStart: Date?

    var body: some View {
        // 毎フレーム変わらない値は、時刻を進める前に 1 回だけ求める（候補の並べ直しをフレームごとにしない）
        let colors = model.capsuleColorIndexes.map(Color.dgCapsule(at:))
        let winnerIndex = model.winnerCapsuleIndex
        let winnerColor = Color.dgCapsule(at: model.winnerColorIndex)
        let isLeverEnabled = model.canTurnLever
        // 「視差効果を減らす」では筐体を動かさないので、時刻を進めない（止まった絵を毎フレーム描き直さない）
        TimelineView(.animation(minimumInterval: nil, paused: !model.phase.isAnimating || reduceMotion)) { context in
            let spinTime = spinStart.map { context.date.timeIntervalSince($0) }
            let dropTime = dropStart.map { context.date.timeIntervalSince($0) }
            let openTime = openStart.map { context.date.timeIntervalSince($0) }
            DGGachaMachine(
                capsuleColors: colors,
                dispensedColor: dropTime == nil || reduceMotion ? nil : winnerColor,
                isLeverEnabled: isLeverEnabled,
                pose: GachaMotion.machinePose(
                    times: GachaMotion.StageTimes(spin: spinTime, drop: dropTime, open: openTime),
                    capsuleCount: colors.count,
                    winnerIndex: winnerIndex,
                    reduceMotion: reduceMotion
                ),
                onTurnLever: { model.leverTapped() }
            )
        }
        .onAppear {
            // 見終えた抽選で開いたときは、初めから開けるところから始まることがある
            start(model.phase, at: .now)
        }
        .onChange(of: model.phase) { _, phase in
            start(phase, at: .now)
        }
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
            // 回し始めた時刻は残す（落ち始めから揺れとかき混ぜを収めるのに使う）
            dropStart = dropStart ?? date
        case .opening, .opened:
            // 落とさずに開けるところから始めたとき（見終えた抽選）は、落ち終えたことにする
            dropStart = dropStart ?? .distantPast
            openStart = openStart ?? date
        }
    }
}
