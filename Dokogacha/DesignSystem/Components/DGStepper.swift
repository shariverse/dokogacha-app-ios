//
//  DGStepper.swift
//  Dokogacha
//
//  数を 1 ずつ増減する部品（`04_design_system.md` の §4 の Stepper）。S-03・S-12 の「1人あたりの投稿数」で使う。
//

import SwiftUI

/// −／＋ のボタンと、中央の「3 件まで」の表示で、決まった範囲の整数を選ぶ部品。
///
/// 白・線 2・角丸 14・内側 8。−／＋ は 44×44（角丸 12・線 2・`bg.base`）。中央は数値（見出し 22）＋単位（本文 Black 14）。
/// 範囲の端ではボタンを無効にする（S-12 の「現在値未満は選べない」は、範囲の下限を現在値にして渡す）。
/// VoiceOver では、中央を「何の値か」の名前（`valueLabel`）と「3件まで」の値を持つ 1 つの調整可能な要素として読み、上下のスワイプでも増減できる。
struct DGStepper: View {
    /// 外枠の角丸
    private static let containerRadius: CGFloat = 14
    /// 中央の数値の大きさ（見出し）
    private static let valueFontSize: CGFloat = 22
    /// −／＋ の記号の大きさ
    private static let glyphFontSize: CGFloat = 22

    /// 選んでいる値
    @Binding var value: Int
    /// 選べる範囲
    let range: ClosedRange<Int>
    /// 数値の後ろに付ける単位（「件まで」）
    let unit: LocalizedStringKey
    /// 中央の値の VoiceOver の名前（何の値か。「1人あたりの投稿数」）
    let valueLabel: LocalizedStringKey
    /// − のボタンの VoiceOver の名前（「投稿数を減らす」）
    let decrementLabel: LocalizedStringKey
    /// ＋ のボタンの VoiceOver の名前（「投稿数を増やす」）
    let incrementLabel: LocalizedStringKey

    /// 部品ごと無効にされたか（`.disabled(true)`。S-12 で作成者以外・終了したルームのとき）。無効なら両方のボタン・中央の値・外枠を無効の色にする
    @Environment(\.isEnabled) private var isEnvironmentEnabled

    var body: some View {
        HStack(spacing: DGSpacing.s12) {
            stepButton(glyph: "−", label: decrementLabel, isEnabled: isEnvironmentEnabled && DGStepperRule.canDecrement(value, in: range)) {
                value = DGStepperRule.decremented(value, in: range)
            }
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s4) {
                Text(value, format: .number)
                    .font(.dgDisplay(Self.valueFontSize, relativeTo: .title2))
                Text(unit)
                    .font(.dgBody(14, weight: .black, relativeTo: .body))
            }
            // 部品ごと無効なら、中央の値も無効の文字の色にする（変えられないことを見た目でも示す）
            .foregroundStyle(isEnvironmentEnabled ? Color.dgInk : Color.dgTextDisabled)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(valueLabel))
            .accessibilityValue(Text(value, format: .number) + Text(unit))
            .accessibilityAdjustableAction { direction in
                // 部品ごと無効なときは、VoiceOver の上下のスワイプでも変えない
                guard isEnvironmentEnabled else {
                    return
                }
                switch direction {
                case .increment: value = DGStepperRule.incremented(value, in: range)
                case .decrement: value = DGStepperRule.decremented(value, in: range)
                @unknown default: break
                }
            }
            stepButton(glyph: "＋", label: incrementLabel, isEnabled: isEnvironmentEnabled && DGStepperRule.canIncrement(value, in: range)) {
                value = DGStepperRule.incremented(value, in: range)
            }
        }
        .padding(DGSpacing.s8)
        .background(
            isEnvironmentEnabled ? Color.dgSurfaceCard : Color.dgSurfaceDisabled,
            in: RoundedRectangle(cornerRadius: Self.containerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.containerRadius)
                .strokeBorder(isEnvironmentEnabled ? Color.dgInk : Color.dgSurfaceDisabled, lineWidth: DGBorder.regular)
        )
    }

    /// −／＋ のボタン。範囲の端では無効の色（`surface.disabled`・`text.disabled`・縁も背景と同じ色）にする
    private func stepButton(
        glyph: String,
        label: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.sm)
        return Button(action: action) {
            Text(verbatim: glyph)
                .font(.dgBody(Self.glyphFontSize, weight: .black, relativeTo: .title2))
                .foregroundStyle(isEnabled ? Color.dgInk : Color.dgTextDisabled)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .background(isEnabled ? Color.dgBgBase : Color.dgSurfaceDisabled, in: shape)
                .overlay(shape.strokeBorder(isEnabled ? Color.dgInk : Color.dgSurfaceDisabled, lineWidth: DGBorder.regular))
                .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(label))
    }
}

/// Stepper の増減の判定（範囲の端で止める）。
///
/// 範囲の外の値が渡されても（設定の変更などで上限が下がったとき）、範囲の中に戻す向きにだけ動かす。
nonisolated enum DGStepperRule {
    /// 減らせるか（下限より大きいか）
    static func canDecrement(_ value: Int, in range: ClosedRange<Int>) -> Bool {
        value > range.lowerBound
    }

    /// 増やせるか（上限より小さいか）
    static func canIncrement(_ value: Int, in range: ClosedRange<Int>) -> Bool {
        value < range.upperBound
    }

    /// 1 減らした値。範囲の中に収める
    static func decremented(_ value: Int, in range: ClosedRange<Int>) -> Int {
        clamped(value - 1, in: range)
    }

    /// 1 増やした値。範囲の中に収める
    static func incremented(_ value: Int, in range: ClosedRange<Int>) -> Int {
        clamped(value + 1, in: range)
    }

    /// 範囲の中に収めた値
    static func clamped(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

#Preview("Stepper 状態ごと") {
    @Previewable @State var middle = 3
    @Previewable @State var lower = 1
    @Previewable @State var upper = 10
    VStack(spacing: DGSpacing.s16) {
        DGStepper(
            value: $middle,
            range: 1...10,
            unit: "件まで",
            valueLabel: "1人あたりの投稿数",
            decrementLabel: "投稿数を減らす",
            incrementLabel: "投稿数を増やす"
        )
        DGStepper(
            value: $lower,
            range: 1...10,
            unit: "件まで",
            valueLabel: "1人あたりの投稿数",
            decrementLabel: "投稿数を減らす",
            incrementLabel: "投稿数を増やす"
        )
        DGStepper(
            value: $upper,
            range: 1...10,
            unit: "件まで",
            valueLabel: "1人あたりの投稿数",
            decrementLabel: "投稿数を減らす",
            incrementLabel: "投稿数を増やす"
        )
        DGStepper(
            value: $middle,
            range: 1...10,
            unit: "件まで",
            valueLabel: "1人あたりの投稿数",
            decrementLabel: "投稿数を減らす",
            incrementLabel: "投稿数を増やす"
        )
        .dynamicTypeSize(.accessibility5)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
