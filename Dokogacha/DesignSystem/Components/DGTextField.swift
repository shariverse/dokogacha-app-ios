//
//  DGTextField.swift
//  Dokogacha
//
//  1 行の入力欄（表示名 S-01・ルーム名 S-03 など）。
//  04 の §1「`surface.card`：カード・入力欄」、§3「`radius.m`：入力欄」と、主要な要素の太い墨色の線（デザインの原則 1）で作る。
//

import SwiftUI

/// ラベル・文字数・入力欄・補足・エラーを縦に並べた 1 行の入力欄。
///
/// - 文字数は「n/上限」を見出しフォントで右上に出す（04 の §2「数字（カウント）も見出しフォント」）。上限を超えたら朱色にする
/// - `errorMessage` があるときは、縁と文字数を朱色（`accent.text`）にし、補足の下にエラーの文言を出す（色だけで伝えない）
/// - VoiceOver では入力欄の名前をラベルにし、文字数と補足・エラーを値の後に読む
struct DGTextField: View {
    /// 入力欄の上のラベル（03 の表記）
    let label: LocalizedStringKey
    /// プレースホルダ（03 の表記）
    let placeholder: LocalizedStringKey
    /// 入力中の文字列
    @Binding var text: String
    /// いまの文字数（検証の規則で数えたもの。呼び出し側が決める）
    let count: Int
    /// 文字数の上限
    let limit: Int
    /// 入力欄の下の補足。無ければ nil
    var hint: LocalizedStringKey?
    /// 入力が正しくないときの文言。正しい・空のときは nil
    var errorMessage: LocalizedStringKey?
    /// UI テストが入力欄を探す ID。無ければ nil
    var identifier: String?
    /// 文字数（「n/上限」）を出すか（上限が画面の目安にならない入力（参考 URL）では出さない）
    var showsCount = true

    /// ラベルの文字の大きさ（本文 Bold 14）
    private static let labelSize: CGFloat = 14
    /// 入力する文字の大きさ（本文 Bold 16）
    private static let inputSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s6) {
            // 文字が大きいときはラベルと文字数を縦に並べ、どちらも切らない
            if showsCount {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        labelText
                        Spacer(minLength: DGSpacing.s8)
                        counter
                    }
                    VStack(alignment: .leading, spacing: DGSpacing.s4) {
                        labelText
                        counter
                    }
                }
            } else {
                labelText
            }
            field
            if let hint {
                Text(hint)
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Color.dgAccentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 入力が正しくない・上限を超えたか
    private var isInvalid: Bool {
        errorMessage != nil || count > limit
    }

    private var labelText: some View {
        Text(label)
            .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.dgInk)
            .accessibilityHidden(true)
    }

    private var counter: some View {
        Text(verbatim: "\(count)/\(limit)")
            .font(.dg(.displayTag))
            .foregroundStyle(count > limit ? Color.dgAccentText : Color.dgTextSecondary)
            .monospacedDigit()
            // 入力欄の値と一緒に読むので、ここでは読まない
            .accessibilityHidden(true)
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Color.dgTextSecondary))
            .font(.dgBody(Self.inputSize, weight: .bold, relativeTo: .body))
            .foregroundStyle(Color.dgInk)
            .tint(Color.dgAccentPrimary)
            .padding(.horizontal, DGSpacing.s14)
            .padding(.vertical, DGSpacing.s10)
            .frame(minHeight: DGMetrics.minTapTarget)
            .background(Color.dgSurfaceCard, in: shape)
            .overlay { shape.strokeBorder(isInvalid ? Color.dgAccentText : Color.dgInk, lineWidth: DGBorder.regular) }
            .accessibilityHint(accessibilityHint)
            .accessibilityIdentifier(identifier ?? "")
    }

    /// VoiceOver で値の後に読む文言（文字数・エラー・補足）
    private var accessibilityHint: Text {
        var parts: [Text] = []
        if showsCount {
            parts.append(Text("\(limit)文字中\(count)文字"))
        }
        if let errorMessage {
            parts.append(Text(errorMessage))
        }
        if let hint {
            parts.append(Text(hint))
        }
        guard var hintText = parts.first else {
            return Text(verbatim: "")
        }
        for part in parts.dropFirst() {
            hintText = hintText + Text(verbatim: "、") + part
        }
        return hintText
    }
}

#Preview("TextField") {
    @Previewable @State var empty = ""
    @Previewable @State var filled = "ゆい"
    @Previewable @State var over = "とてもながいなまえのひと"
    VStack(spacing: DGSpacing.s24) {
        DGTextField(label: "表示名", placeholder: "例：ゆい", text: $empty, count: 0, limit: 10, hint: "ルームのメンバーに表示されます")
        DGTextField(label: "表示名", placeholder: "例：ゆい", text: $filled, count: 2, limit: 10, hint: "ルームのメンバーに表示されます")
        DGTextField(
            label: "表示名",
            placeholder: "例：ゆい",
            text: $over,
            count: 12,
            limit: 10,
            hint: "ルームのメンバーに表示されます",
            errorMessage: "10文字以内で入力してください"
        )
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
