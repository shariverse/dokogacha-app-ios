//
//  DisplayNameField.swift
//  Dokogacha
//

import SwiftUI

/// 表示名の入力欄（S-01 の登録と S-15 の変更で共通）。
///
/// ラベル「表示名」・プレースホルダ「例：ゆい」・補足「ルームのメンバーに表示されます」（03 の S-01 の 3）と、
/// 検証の結果（`NameInputCheck`）から文字数とエラーの文言を出す。どちらの画面でも同じ文言・同じ数え方にするため 1 つにまとめる。
struct DisplayNameField: View {
    /// 入力中の表示名
    @Binding var text: String
    /// 入力の検証の結果
    let check: NameInputCheck
    /// UI テストが入力欄を探す ID
    let identifier: String

    var body: some View {
        DGTextField(
            label: "表示名",
            placeholder: "例：ゆい",
            text: $text,
            count: check.characterCount,
            limit: check.limit,
            hint: "ルームのメンバーに表示されます",
            errorMessage: issueMessage,
            identifier: identifier
        )
    }

    /// 入力が正しくないときの文言
    private var issueMessage: LocalizedStringKey? {
        switch check.issue {
        case let .tooLong(limit):
            "\(limit)文字以内で入力してください"
        case .forbiddenCharacter:
            "使えない文字が含まれています"
        case nil:
            nil
        }
    }
}

#Preview("表示名の入力欄") {
    @Previewable @State var name = "とてもながいなまえのひと"
    DisplayNameField(text: $name, check: NameInputCheck(name, length: DomainConstants.Limits.displayNameLength), identifier: "preview")
        .padding(DGSpacing.screenX)
        .frame(maxHeight: .infinity)
        .background(Color.dgBgBase)
}
