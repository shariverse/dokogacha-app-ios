//
//  PlaceMapExpandBadge.swift
//  Dokogacha
//

import SwiftUI

/// S-09・S-10 の小さな地図の右上に重ねる拡大のアイコン（押すと S-17 場所の地図を開けることを示す）。
///
/// 白い丸に墨色の縁。飾りなので VoiceOver では読まず（ボタンのラベル「<場所名>の地図を開く」で読む）、
/// 文字の大きさでは大きさを変えない（大きくすると小さな地図を覆うため）
struct PlaceMapExpandBadge: View {
    /// アイコンの大きさ
    private static let iconSize: CGFloat = 14
    /// 丸の一辺
    private static let side: CGFloat = 32

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: Self.iconSize))
            .fontWeight(.bold)
            .foregroundStyle(Color.dgInk)
            .frame(width: Self.side, height: Self.side)
            .background(Color.dgSurfaceCard, in: Circle())
            .overlay { Circle().strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
            .accessibilityHidden(true)
    }
}

#Preview("拡大のアイコン") {
    PlaceMapExpandBadge()
        .padding(DGSpacing.s16)
        .background(Color.dgBgBase)
}
