//
//  PlaceSearchChip.swift
//  Dokogacha
//

import SwiftUI

/// S-08 のチップ 1 つ（クイックカテゴリ・検索のエリア）。選んでいるものは墨色で塗る。
///
/// 見た目はプロトタイプのクイックカテゴリ（高さ 34・角丸 10・文字 12 Black・線 2）。見た目の上下を広げて、タップ領域を 44 にする。
/// 押すとシートを出すチップ（市区町村を選ぶ）は、文字の後ろに下向きの山の印を付ける
struct PlaceSearchChip: View {
    /// 見た目の高さ（プロトタイプの 34。タップ領域は上下を広げて 44）
    static let height: CGFloat = 34
    /// 角丸（プロトタイプの 10）
    static let radius: CGFloat = 10
    /// 文字の大きさ（プロトタイプの 12）
    static let textSize: CGFloat = 12
    /// 後ろの印の大きさ（文字より少し小さく）
    private static let symbolSize: CGFloat = 10

    /// 文字
    let title: String
    /// 選んでいるか
    let isSelected: Bool
    /// 文字の後ろの印（SF Symbols の名前）。無ければ nil
    var trailingSymbol: String?
    /// 押したときの処理
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var symbolSize = PlaceSearchChip.symbolSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius)
        Button(action: action) {
            HStack(spacing: DGSpacing.s4) {
                Text(verbatim: title)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: symbolSize))
                        .fontWeight(.bold)
                        .accessibilityHidden(true)
                }
            }
            .font(.dgBody(Self.textSize, weight: .black, relativeTo: .caption))
            .foregroundStyle(isSelected ? Color.dgTextOnAccent : Color.dgInk)
            .padding(.horizontal, DGSpacing.s12)
            .frame(minHeight: Self.height)
            .background(isSelected ? Color.dgInk : Color.dgSurfaceCard, in: shape)
            .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
            // 見た目の 34 の上下を広げて、タップ領域を 44 にする
            .padding(.vertical, (DGMetrics.minTapTarget - Self.height) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("S-08 のチップ") {
    HStack(spacing: DGSpacing.s6) {
        PlaceSearchChip(title: "全国", isSelected: false) {}
        PlaceSearchChip(title: "関東", isSelected: true) {}
        PlaceSearchChip(title: "選ぶ", isSelected: false, trailingSymbol: "chevron.down") {}
        PlaceSearchChip(title: "豊島区", isSelected: true, trailingSymbol: "chevron.down") {}
    }
    .padding(DGSpacing.screenX)
    .background(Color.dgBgBase)
}
