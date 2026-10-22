//
//  DGAdPlaceholder.swift
//  Dokogacha
//
//  バナー広告の場所を示す固定の見た目の枠（`04_design_system.md` の `surface.ad`・`line.dashedStrong`。プロトタイプの広告枠）。
//

import SwiftUI

/// バナー広告の代わりに出す枠。撮影モードで `-screenshot-ad-placeholder` を付けたとき（PR のスクリーンショット）に、本物の広告を写さずにバナーの場所を見せる。
///
/// 背景 `surface.ad`・点線の縁 `line.dashedStrong`・「広告」のラベル。高さはバナーの目安の 50（03 の §3）。
struct DGAdPlaceholder: View {
    /// 高さ（03 の §3「目安50pt」。320×50 のバナー）
    static let height: CGFloat = 50
    /// 角丸
    private static let cornerRadius: CGFloat = DGRadius.sm
    /// 点線の刻み（`DGButton` の `dashed` と同じ）
    private static let dash: [CGFloat] = [6, 4]
    /// ラベルの文字の大きさ（プロトタイプの 12）
    private static let labelSize: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Text("広告")
            .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.dgTextSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(Color.dgSurfaceAd, in: shape)
            .overlay {
                shape.strokeBorder(Color.dgLineDashedStrong, style: StrokeStyle(lineWidth: DGBorder.regular, dash: Self.dash))
            }
            .accessibilityElement(children: .combine)
    }
}

#Preview("AdPlaceholder") {
    DGAdPlaceholder()
        .padding(DGSpacing.screenX)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .background(Color.dgBgBase)
}
