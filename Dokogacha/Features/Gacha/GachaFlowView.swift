//
//  GachaFlowView.swift
//  Dokogacha
//

import SwiftUI

/// S-13 ガチャと S-14 結果を行き来するフルスクリーンカバーの中身（03 の §2「S-13 → カプセルをタップ → S-14」「S-14 → 引き直し可決 → S-13」）。
///
/// カプセルを開け終えたら、カバーを閉じずに同じカバーの中で S-14 に替える（カバーを閉じて出し直すと、間にルームの画面が一瞬見えるため）。
/// 引き直しが可決して S-14 の「ガチャを回す」が押されたら、同じカバーの中で S-13 に戻す（新しい S-13 は、除外の後の候補で待機から始まる）。
/// `drawn`・`closed` のルームを開いたとき（`AppRoute.result`）は S-14 から始める。
/// 「視差効果を減らす」ではフェード（0.2 秒）で、そうでなければ少し長めのフェードで替える
struct GachaFlowView<Gacha: View, Result: View>: View {
    /// 出している画面
    enum Stage: Hashable {
        /// S-13（何回目か。S-14 から戻るたびに増やし、新しい S-13 として作り直す）
        case gacha(round: Int)
        /// S-14（抽選の ID）
        case result(drawID: String, round: Int)
    }

    /// S-13（カプセルを開け終えたら抽選の ID を渡す処理を受け取る）
    private let gacha: (@escaping (String) -> Void) -> Gacha
    /// S-14（抽選の ID と、引き直しの可決の後に S-13 に戻る処理を受け取る）
    private let result: (String, @escaping () -> Void) -> Result

    /// 出している画面
    @State private var stage: Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - drawID: S-14 から始めるときの抽選の ID（nil なら S-13 から始める）
    ///   - gacha: S-13 を作る
    ///   - result: S-14 を作る
    init(
        startingWith drawID: String? = nil,
        gacha: @escaping (@escaping (String) -> Void) -> Gacha,
        result: @escaping (String, @escaping () -> Void) -> Result
    ) {
        self.gacha = gacha
        self.result = result
        _stage = State(initialValue: drawID.map { .result(drawID: $0, round: 0) } ?? .gacha(round: 0))
    }

    var body: some View {
        ZStack {
            switch stage {
            case let .gacha(round):
                gacha { drawID in
                    move(to: .result(drawID: drawID, round: round))
                }
                .id(stage)
                .transition(.opacity)
            case let .result(drawID, round):
                result(drawID) {
                    move(to: .gacha(round: round + 1))
                }
                .id(stage)
                .transition(.opacity)
            }
        }
    }

    /// 画面を替える
    private func move(to next: Stage) {
        withAnimation(reduceMotion ? DGMotion.reducedFade : .easeInOut(duration: DGMotion.pop.duration)) {
            stage = next
        }
    }
}
