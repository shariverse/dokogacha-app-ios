//
//  GachaFlowView.swift
//  Dokogacha
//

import SwiftUI

/// S-13 ガチャから S-14 結果へ進むフルスクリーンカバーの中身（03 の §2「S-13 → カプセルをタップ → S-14」）。
///
/// カプセルを開け終えたら、カバーを閉じずに同じカバーの中で S-14 に替える（カバーを閉じて出し直すと、間にルームの画面が一瞬見えるため）。
/// 「視差効果を減らす」ではフェード（0.2 秒）で、そうでなければ少し長めのフェードで替える
struct GachaFlowView<Gacha: View, Result: View>: View {
    /// S-13（カプセルを開け終えたら抽選の ID を渡す処理を受け取る）
    private let gacha: (@escaping (String) -> Void) -> Gacha
    /// S-14（抽選の ID を受け取る）
    private let result: (String) -> Result

    /// 開け終えた抽選の ID（まだなら S-13 を出す）
    @State private var openedDrawID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - gacha: S-13 を作る
    ///   - result: S-14 を作る
    init(gacha: @escaping (@escaping (String) -> Void) -> Gacha, result: @escaping (String) -> Result) {
        self.gacha = gacha
        self.result = result
    }

    var body: some View {
        ZStack {
            if let openedDrawID {
                result(openedDrawID)
                    .transition(.opacity)
            } else {
                gacha { drawID in
                    withAnimation(reduceMotion ? DGMotion.reducedFade : .easeInOut(duration: DGMotion.pop.duration)) {
                        openedDrawID = drawID
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
