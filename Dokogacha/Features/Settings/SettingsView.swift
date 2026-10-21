//
//  SettingsView.swift
//  Dokogacha
//

import SwiftUI

/// S-15 設定（プッシュ）。03 の S-15 の並びで、項目を白いカードにまとめて縦にスクロールで並べる。
///
/// - 表示名の行を押すと、編集のシート（`DisplayNameEditor`）を出す（02 の F-01「表示名は設定画面から変更できる」）
/// - 広告非表示の購入と復元・Apple の連携・通知設定・利用規約・プライバシーポリシー・ライセンス・アカウント削除は、
///   置き場所だけを先に作り「準備中」と出す（押しても何もしない）。タスク 38・39 で中身に差し替える
/// - バージョンはアプリの `CFBundleShortVersionString` を出す
///
/// 標準のナビゲーションバーは使わず、画面のヘッダー（`DGHeader`）を置く（03 の §3）。
struct SettingsView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 設定の画面
        static let screen = "settings.screen"
        /// 表示名の行
        static let displayName = "settings.displayName"
    }

    @State private var model: SettingsModel
    /// 編集のシートにもトーストを重ねるための窓口（シートは画面の根元のトーストより上に出るため）
    private let toasts: DGToastCenter

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: 通信エラーを出すトーストの窓口（`model` に渡したものと同じ）
    init(model: SettingsModel, toasts: DGToastCenter) {
        _model = State(initialValue: model)
        self.toasts = toasts
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("設定"), onBack: { dismiss() })
            ScrollView {
                VStack(spacing: DGSpacing.s16) {
                    profileSection
                    purchaseSection
                    SettingsSection {
                        SettingsRow(title: Text("Apple でサインインを連携"), accessory: .pending)
                    }
                    SettingsSection {
                        SettingsRow(title: Text("通知設定"), accessory: .pending)
                    }
                    aboutSection
                    SettingsSection {
                        SettingsRow(title: Text("アカウントを削除"), accessory: .pending, isDestructive: true)
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, DGSpacing.s8)
                .padding(.bottom, DGSpacing.s24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .task {
            await model.observe()
        }
        .sheet(isPresented: $model.isEditingName) {
            DisplayNameEditor(model: model)
                .dgToast(toasts)
        }
    }

    /// 表示名（押すと編集のシート）。今の名前が届くまでは、行の形を保ったまま読み込み中の形で出す
    private var profileSection: some View {
        SettingsSection {
            Button {
                model.beginEditingName()
            } label: {
                SettingsRow(
                    title: Text("表示名"),
                    value: Text(verbatim: model.displayName ?? String(localized: "読み込み中")),
                    accessory: .disclosure
                )
                .redacted(reason: model.hasLoadedProfile ? [] : .placeholder)
            }
            .buttonStyle(.dgBare)
            .disabled(!model.canEditName)
            .accessibilityHint(Text("表示名を変更します"))
            .accessibilityIdentifier(Identifier.displayName)
        }
    }

    /// 広告非表示の購入と復元（タスク 38）
    private var purchaseSection: some View {
        SettingsSection {
            SettingsRow(title: Text("広告を非表示にする（¥\(DomainConstants.RemoveAds.priceYen)）"), accessory: .pending)
            DGDashedLine()
            SettingsRow(title: Text("購入を復元"), accessory: .pending)
        }
    }

    /// 利用規約・プライバシーポリシー・ライセンス（タスク 38）とバージョン
    private var aboutSection: some View {
        SettingsSection {
            SettingsRow(title: Text("利用規約"), accessory: .pending)
            DGDashedLine()
            SettingsRow(title: Text("プライバシーポリシー"), accessory: .pending)
            DGDashedLine()
            SettingsRow(title: Text("ライセンス"), accessory: .pending)
            DGDashedLine()
            SettingsRow(title: Text("バージョン"), value: Text(verbatim: Self.appVersion))
        }
    }

    /// アプリのバージョン（`CFBundleShortVersionString`）。読めなければ空
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

/// プレビュー用の S-15（擬似のサーバーの `one-room` のデータ）
@MainActor private func settingsPreview() -> some View {
    let toasts = DGToastCenter()
    let model = SettingsModel(userID: DemoScenario.myUserID, auth: InMemoryServer.demo(.oneRoom), toasts: toasts)
    return NavigationStack {
        SettingsView(model: model, toasts: toasts)
    }
    .dgToast(toasts)
}

#Preview("S-15") {
    settingsPreview()
}

#Preview("S-15 文字を最大") {
    settingsPreview()
        .dynamicTypeSize(.accessibility5)
}
