//
//  DGSegmentedChoice.swift
//  Dokogacha
//
//  等幅の選択肢（`04_design_system.md` の §4 の SegmentedChoice）。S-03・S-12 の「ガチャ解禁の条件」「いいねの効き方」で使う。
//

import SwiftUI

/// 等幅のボタンを並べ、選んだものを朱色で示す選択肢。
///
/// 間隔 8、各ボタンは高さ 48・角丸 12・線 2。選択中は `accent.primary` に白文字、非選択は白に墨色の文字。
/// 文字が大きくなって折り返したときも、ボタンの高さはそろえる。
/// 無効（`.disabled(true)`。S-12 の状態で変えられない項目）のときは、Stepper の無効のボタンと同じ `surface.disabled` の背景にし、
/// 選択中は `text.disabled` の背景に白文字で示す（選んでいる値は読めるまま、押せないことが色で分かるように）。
struct DGSegmentedChoice<Value: Hashable>: View {
    /// ボタンの最小の高さ
    private static var buttonHeight: CGFloat { 48 }

    /// 選んでいる値
    @Binding var selection: Value
    /// 並べる選択肢
    let options: [DGChoiceOption<Value>]

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: DGSpacing.s8) {
            ForEach(options) { option in
                choice(option)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 選択肢 1 つ分のボタン
    private func choice(_ option: DGChoiceOption<Value>) -> some View {
        let isSelected = option.value == selection
        let shape = RoundedRectangle(cornerRadius: DGRadius.sm)
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.dgBody(13, weight: .black, relativeTo: .body))
                .foregroundStyle(foreground(isSelected: isSelected))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DGSpacing.s6)
                .padding(.vertical, DGSpacing.s4)
                .frame(maxWidth: .infinity, minHeight: Self.buttonHeight, maxHeight: .infinity)
                .background(background(isSelected: isSelected), in: shape)
                .overlay(shape.strokeBorder(isEnabled ? Color.dgInk : Color.dgTextDisabled, lineWidth: DGBorder.regular))
                .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 文字の色（選択中は白。無効の非選択は `text.disabled`）
    private func foreground(isSelected: Bool) -> Color {
        if isSelected {
            return .dgTextOnAccent
        }
        return isEnabled ? .dgInk : .dgTextDisabled
    }

    /// 背景の色（有効: 選択中 `accent.primary`・非選択 `surface.card`。無効: 選択中 `text.disabled`・非選択 `surface.disabled`）
    private func background(isSelected: Bool) -> Color {
        switch (isEnabled, isSelected) {
        case (true, true): .dgAccentPrimary
        case (true, false): .dgSurfaceCard
        case (false, true): .dgTextDisabled
        case (false, false): .dgSurfaceDisabled
        }
    }
}

/// Preview 用の解禁の条件（S-03 の 3 択）
private enum PreviewUnlockCondition: Hashable {
    case all
    case majority
    case deadline
}

/// Preview 用のいいねの効き方（S-03 の 2 択）
private enum PreviewLikeMode: Hashable {
    case boost
    case equal
}

#Preview("SegmentedChoice") {
    @Previewable @State var condition = PreviewUnlockCondition.all
    @Previewable @State var mode = PreviewLikeMode.equal
    VStack(spacing: DGSpacing.s24) {
        DGSegmentedChoice(
            selection: $condition,
            options: [
                DGChoiceOption("全員OK", value: .all),
                DGChoiceOption("過半数OK", value: .majority),
                DGChoiceOption("締切日時", value: .deadline)
            ]
        )
        DGSegmentedChoice(
            selection: $mode,
            options: [
                DGChoiceOption("共感ブースト", value: .boost),
                DGChoiceOption("みんな平等", value: .equal)
            ]
        )
        DGSegmentedChoice(
            selection: $mode,
            options: [
                DGChoiceOption("共感ブースト", value: .boost),
                DGChoiceOption("みんな平等", value: .equal)
            ]
        )
        .disabled(true)
        DGSegmentedChoice(
            selection: $condition,
            options: [
                DGChoiceOption("全員OK", value: .all),
                DGChoiceOption("過半数OK", value: .majority),
                DGChoiceOption("締切日時", value: .deadline)
            ]
        )
        .dynamicTypeSize(.accessibility5)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
