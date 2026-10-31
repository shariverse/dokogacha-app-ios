//
//  RoomGachaBar.swift
//  Dokogacha
//

import SwiftUI

/// S-07 ルームの下部に固定するボタン（03 の S-07 の GachaCTA）。
///
/// 解禁時「ガチャを回す」／未解禁時「準備OKが揃うと回せます」（無効）。行き先が決まった（`drawn`・`closed`）ルームでは、
/// 結果（S-14）を閉じた後にもう一度見られるよう「行き先きっぷを見る」を出す（03 の S-07 には無い。S-14 から戻った後の入口として足した）。
/// 作成者が抽選の前に途中で終了したルームでは、押せない「このルームは終了しています」を出す（Discussion #155）。
/// 読み込み中は出さない
struct RoomGachaBar: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 「ガチャを回す」「準備OKが揃うと回せます」
        static let gacha = "room.gacha"
        /// 「行き先きっぷを見る」
        static let result = "room.result"
        /// 「このルームは終了しています」（行き先が決まらないまま終了したルーム）
        static let ended = "room.ended"
    }

    /// ボタンの状態（nil なら出さない）
    let state: RoomModel.GachaButtonState?
    /// 「ガチャを回す」が押された
    let onGacha: () -> Void
    /// 「行き先きっぷを見る」が押された（抽選の ID）
    let onResult: (String) -> Void

    var body: some View {
        if let state {
            button(state)
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.vertical, DGSpacing.s10)
                .dgContentColumn()
                .background(Color.dgBgBase)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.dgInk)
                        .frame(height: DGBorder.regular)
                }
        }
    }

    /// 状態ごとのボタン
    @ViewBuilder
    private func button(_ state: RoomModel.GachaButtonState) -> some View {
        switch state {
        case .ready:
            DGButton("ガチャを回す", action: onGacha)
                .accessibilityIdentifier(Identifier.gacha)
        case .waiting:
            DGButton("準備OKが揃うと回せます") {}
                .disabled(true)
                .accessibilityIdentifier(Identifier.gacha)
        case let .result(drawID):
            DGButton("行き先きっぷを見る") {
                onResult(drawID)
            }
            .accessibilityIdentifier(Identifier.result)
        case .ended:
            // 押せるものが無いので、ボタンではない状態の表示にする（VoiceOver で「淡色表示、ボタン」と読ませない）
            DGButtonShapedStatus(title: "このルームは終了しています")
                .accessibilityIdentifier(Identifier.ended)
        }
    }
}
