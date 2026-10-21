//
//  DisplayNameEditor.swift
//  Dokogacha
//

import SwiftUI

/// S-15 の表示名の変更のシート。今の名前を入れた入力欄（S-01 と同じ `DisplayNameField`）と「保存」を出す。
///
/// 「保存」は入力が正しく今の名前と違うときだけ押せる（`SettingsModel.canSave`）。保存できたらシートを閉じ、
/// 失敗したらトーストを出して開いたままにする。シートが消えたら送っている途中の保存を止める。
struct DisplayNameEditor: View {
    /// UI テストが探す ID
    enum Identifier {
        /// シート
        static let sheet = "settings.nameEditor"
        /// 表示名の入力欄
        static let field = "settings.nameEditor.field"
        /// 「保存」
        static let save = "settings.nameEditor.save"
    }

    /// 閉じるアイコンの大きさ
    private static let closeIconSize: CGFloat = 20

    @Bindable var model: SettingsModel

    @FocusState private var isFieldFocused: Bool
    @ScaledMetric(relativeTo: .headline) private var closeIconSize = DisplayNameEditor.closeIconSize

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("表示名の変更"), onBack: nil) {
                closeButton
            }
            .padding(.leading, DGSpacing.s12)
            ScrollView {
                DisplayNameField(text: $model.draftName, check: model.draftCheck, identifier: Identifier.field)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { model.saveTapped() }
                    .disabled(model.isSaving)
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.vertical, DGSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("保存") {
                model.saveTapped()
            }
            .disabled(!model.canSave)
            .accessibilityIdentifier(Identifier.save)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .background(Color.dgBgBase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.sheet)
        .onAppear { isFieldFocused = true }
        // 閉じた・下に引いて消したら、送っている途中の保存を止める
        .onDisappear { model.cancelSave() }
    }

    /// 右端の閉じるボタン（変えずに閉じる）
    private var closeButton: some View {
        Button {
            model.isEditingName = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: closeIconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityLabel(Text("閉じる"))
    }
}

#Preview("表示名の変更") {
    let model = SettingsModel(userID: DemoScenario.myUserID, auth: InMemoryServer.demo(.oneRoom), toasts: DGToastCenter())
    model.draftName = "たくみ"
    return DisplayNameEditor(model: model)
}
