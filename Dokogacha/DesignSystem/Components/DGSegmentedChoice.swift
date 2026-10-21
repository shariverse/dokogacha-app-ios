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
struct DGSegmentedChoice<Value: Hashable>: View {
    /// ボタンの最小の高さ
    private static var buttonHeight: CGFloat { 48 }

    /// 選んでいる値
    @Binding var selection: Value
    /// 並べる選択肢
    let options: [DGChoiceOption<Value>]

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
                .foregroundStyle(isSelected ? Color.dgTextOnAccent : Color.dgInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DGSpacing.s6)
                .padding(.vertical, DGSpacing.s4)
                .frame(maxWidth: .infinity, minHeight: Self.buttonHeight, maxHeight: .infinity)
                .background(isSelected ? Color.dgAccentPrimary : Color.dgSurfaceCard, in: shape)
                .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
                .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
