//
//  DGTabSwitch.swift
//  Dokogacha
//
//  タブの切り替え（`04_design_system.md` の §4 の TabSwitch）。S-08 の「場所を探す」「過去のアイデア」で使う。
//

import SwiftUI

/// 下地の上に等幅のタブを並べ、選んだタブを白い面と墨色の縁で示す切り替え。
///
/// 下地 `surface.muted`・角丸 14・内側 4。各タブは高さ 40・角丸 10。
/// 見た目のタブは 40 だが、下地の内側の余白までをタブのボタンに含め、タップ領域を 44 以上にしている。
struct DGTabSwitch<Value: Hashable>: View {
    /// 下地の角丸
    private static var containerRadius: CGFloat { 14 }
    /// タブの角丸
    private static var tabRadius: CGFloat { 10 }
    /// タブの最小の高さ
    private static var tabHeight: CGFloat { 40 }
    /// 下地の内側の余白（タブの間隔も同じ）
    private static var inset: CGFloat { DGSpacing.s4 }

    /// 選んでいるタブの値
    @Binding var selection: Value
    /// 並べるタブ
    let options: [DGChoiceOption<Value>]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                tab(option)
            }
        }
        .padding(.horizontal, Self.inset / 2)
        .background(Color.dgSurfaceMuted, in: RoundedRectangle(cornerRadius: Self.containerRadius))
    }

    /// タブ 1 つ分のボタン
    private func tab(_ option: DGChoiceOption<Value>) -> some View {
        let isSelected = option.value == selection
        let shape = RoundedRectangle(cornerRadius: Self.tabRadius)
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.dgBody(14, weight: .black, relativeTo: .body))
                .foregroundStyle(Color.dgInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DGSpacing.s8)
                .padding(.vertical, DGSpacing.s4)
                .frame(maxWidth: .infinity, minHeight: Self.tabHeight)
                .background(isSelected ? Color.dgSurfaceCard : Color.clear, in: shape)
                .overlay(shape.strokeBorder(isSelected ? Color.dgInk : Color.clear, lineWidth: DGBorder.regular))
                // 内側の余白までをボタンに含めて、タップ領域を広げる
                .padding(.vertical, Self.inset)
                .padding(.horizontal, Self.inset / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Preview 用のタブの値（S-08 のタブ）
private enum PreviewAddTab: Hashable {
    case search
    case past
}

#Preview("TabSwitch") {
    @Previewable @State var search = PreviewAddTab.search
    @Previewable @State var past = PreviewAddTab.past
    let options = [
        DGChoiceOption("場所を探す", value: PreviewAddTab.search),
        DGChoiceOption("過去のアイデア", value: PreviewAddTab.past)
    ]
    VStack(spacing: DGSpacing.s24) {
        DGTabSwitch(selection: $search, options: options)
        DGTabSwitch(selection: $past, options: options)
        DGTabSwitch(selection: $search, options: options)
            .dynamicTypeSize(.accessibility5)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
