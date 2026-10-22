//
//  DeadlinePickerField.swift
//  Dokogacha
//

import SwiftUI

/// 締切日時のピッカー（S-03 ルーム作成・S-12 ルーム設定で共通）。白いカードに「締切日時」と日時ピッカーを並べ、文字が大きいときは縦に並べる。
///
/// 選べる範囲は呼び出し側が `DeadlineSelection` で決めたもの（今から 1 時間後〜30 日後の 5 分前）を渡す。
struct DeadlinePickerField: View {
    /// 選んでいる日時
    @Binding var date: Date
    /// 選べる範囲
    let range: ClosedRange<Date>
    /// UI テストがピッカーを探す ID
    let identifier: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s8) {
                label
                Spacer(minLength: 0)
                picker
            }
            VStack(alignment: .leading, spacing: DGSpacing.s8) {
                label
                picker
            }
        }
        .padding(.horizontal, DGSpacing.s14)
        .padding(.vertical, DGSpacing.s8)
        .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget, alignment: .leading)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
    }

    private var label: some View {
        Text("締切日時")
            .font(.dg(.bodyTitle))
            .foregroundStyle(Color.dgInk)
            .fixedSize(horizontal: false, vertical: true)
            // ピッカーの名前として読むので、ここでは読まない
            .accessibilityHidden(true)
    }

    private var picker: some View {
        DatePicker(
            selection: $date,
            in: range,
            displayedComponents: [.date, .hourAndMinute]
        ) {
            Text("締切日時")
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(Color.dgAccentPrimary)
        .accessibilityIdentifier(identifier)
    }
}
