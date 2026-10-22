//
//  SettingsView.swift
//  Dokogacha
//

import SwiftUI
import UIKit

/// S-15 設定（プッシュ）。03 の S-15 の並びで、項目を白いカードにまとめて縦にスクロールで並べる。
///
/// - 表示名の行を押すと、編集のシート（`DisplayNameEditor`）を出す（02 の F-01「表示名は設定画面から変更できる」）
/// - 「広告を非表示にする（¥480）」「購入を復元」で買い切りの購入と復元（02 の §7.2 F-51）。購入済みなら「広告非表示：購入済み」にして押せなくする
/// - 「Apple でサインインを連携」で Sign in with Apple に連携する（02 の §1 F-01）。連携済みなら「連携済み」にして押せなくする。
///   その Apple ID が別のアカウントで使われていたら、そのアカウントでサインインし直すかを尋ねる
/// - 「通知設定」は iOS の設定アプリのこのアプリの通知の画面を開く（03 の S-15「iOS の設定アプリを開く」。アプリの中にオン／オフは持たない）
/// - 利用規約・プライバシーポリシーは Web のページ（`DomainConstants.Web`）をアプリの中の Safari（`SFSafariViewController`）で開く
/// - ライセンスは、同梱のフォントの OFL と主要なライブラリのライセンスの画面（`LicensesView`）を積む
/// - バージョンはアプリの `CFBundleShortVersionString`（`CFBundleVersion`）を出す
/// - 「アカウントを削除」はタスク 39 で中身を作る（いまは「準備中」）
///
/// 標準のナビゲーションバーは使わず、画面のヘッダー（`DGHeader`）を置く（03 の §3）。
struct SettingsView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 設定の画面
        static let screen = "settings.screen"
        /// 表示名の行
        static let displayName = "settings.displayName"
        /// 「広告を非表示にする（¥480）」／「広告非表示：購入済み」の行
        static let removeAds = "settings.removeAds"
        /// 「購入を復元」の行
        static let restore = "settings.restore"
        /// 「Apple でサインインを連携」の行
        static let appleLink = "settings.appleLink"
        /// 「通知設定」の行
        static let notifications = "settings.notifications"
        /// 「利用規約」の行
        static let terms = "settings.terms"
        /// 「プライバシーポリシー」の行
        static let privacy = "settings.privacy"
        /// 「ライセンス」の行
        static let licenses = "settings.licenses"
        /// 「バージョン」の行
        static let version = "settings.version"
    }

    /// アプリの中の Safari で開く Web のページ
    private enum WebPage: String, Identifiable {
        case terms
        case privacy

        var id: String { rawValue }

        var url: URL? {
            switch self {
            case .terms: URL(string: DomainConstants.Web.termsURL)
            case .privacy: URL(string: DomainConstants.Web.privacyPolicyURL)
            }
        }
    }

    @State private var model: SettingsModel
    /// 開いている Web のページ（利用規約・プライバシーポリシー）
    @State private var webPage: WebPage?
    /// ライセンスの画面を積んでいるか
    @State private var isShowingLicenses = false
    /// 編集のシートにもトーストを重ねるための窓口（シートは画面の根元のトーストより上に出るため）
    private let toasts: DGToastCenter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.authorizationController) private var authorizationController

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
                        appleLinkRow
                    }
                    SettingsSection {
                        notificationsRow
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
        .task {
            await model.loadProduct()
        }
        .sheet(isPresented: $model.isEditingName) {
            DisplayNameEditor(model: model)
                .dgToast(toasts)
        }
        .sheet(item: $webPage) { page in
            if let url = page.url {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .navigationDestination(isPresented: $isShowingLicenses) {
            LicensesView()
        }
        .alert(Text("この Apple ID は別のアカウントで使われています"), isPresented: $model.isConfirmingAccountSwitch) {
            Button("サインインし直す") {
                model.switchAccountConfirmed()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("そのアカウントでサインインし直すと、参加中のルームがそのアカウントのものに切り替わります。今のアカウントには戻れません。")
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

    /// 広告非表示の購入と復元（02 の §7.2 F-51）
    private var purchaseSection: some View {
        SettingsSection {
            removeAdsRow
            DGDashedLine()
            Button {
                model.restoreTapped()
            } label: {
                SettingsRow(title: Text("購入を復元"), accessory: accessory(for: .restore))
            }
            .buttonStyle(.dgBare)
            .disabled(!model.canStartAction)
            .accessibilityIdentifier(Identifier.restore)
        }
    }

    /// 「広告を非表示にする（¥480）」（購入済みなら「広告非表示：購入済み」で押せない）
    @ViewBuilder private var removeAdsRow: some View {
        switch model.removeAdsRow {
        case let .available(price):
            Button {
                model.purchaseTapped()
            } label: {
                SettingsRow(title: Text("広告を非表示にする（\(price)）"), accessory: accessory(for: .purchase))
            }
            .buttonStyle(.dgBare)
            .disabled(!model.canStartAction)
            .accessibilityIdentifier(Identifier.removeAds)
        case .purchased:
            SettingsRow(title: Text("広告非表示：購入済み"))
                .accessibilityIdentifier(Identifier.removeAds)
        }
    }

    /// 「Apple でサインインを連携」（連携済みなら「連携済み」で押せない）
    @ViewBuilder private var appleLinkRow: some View {
        if model.isLinkedWithApple {
            SettingsRow(title: Text("Apple でサインインを連携"), value: Text("連携済み"))
                .accessibilityIdentifier(Identifier.appleLink)
        } else {
            Button {
                model.linkAppleTapped(using: SystemAppleAuthorizer(controller: authorizationController))
            } label: {
                SettingsRow(title: Text("Apple でサインインを連携"), accessory: accessory(for: .linkApple))
            }
            .buttonStyle(.dgBare)
            .disabled(!model.canStartAction)
            .accessibilityHint(Text("機種を変更したときに、同じ Apple ID でサインインすると参加中のルームが戻ります"))
            .accessibilityIdentifier(Identifier.appleLink)
        }
    }

    /// 「通知設定」（iOS の設定アプリのこのアプリの通知の画面を開く）
    private var notificationsRow: some View {
        Button {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                openURL(url)
            }
        } label: {
            SettingsRow(title: Text("通知設定"), accessory: .disclosure)
        }
        .buttonStyle(.dgBare)
        .accessibilityHint(Text("設定アプリを開きます"))
        .accessibilityIdentifier(Identifier.notifications)
    }

    /// 利用規約・プライバシーポリシー・ライセンスとバージョン
    private var aboutSection: some View {
        SettingsSection {
            webRow(Text("利用規約"), page: .terms, identifier: Identifier.terms)
            DGDashedLine()
            webRow(Text("プライバシーポリシー"), page: .privacy, identifier: Identifier.privacy)
            DGDashedLine()
            Button {
                isShowingLicenses = true
            } label: {
                SettingsRow(title: Text("ライセンス"), accessory: .disclosure)
            }
            .buttonStyle(.dgBare)
            .accessibilityIdentifier(Identifier.licenses)
            DGDashedLine()
            SettingsRow(title: Text("バージョン"), value: Text(verbatim: Self.appVersion))
                .accessibilityIdentifier(Identifier.version)
        }
    }

    /// Web のページを開く行
    private func webRow(_ title: Text, page: WebPage, identifier: String) -> some View {
        Button {
            webPage = page
        } label: {
            SettingsRow(title: title, accessory: .disclosure)
        }
        .buttonStyle(.dgBare)
        .accessibilityIdentifier(identifier)
    }

    /// 操作の行の右端の印（その操作を行っている途中なら、くるくる回る印）
    private func accessory(for action: SettingsModel.Action) -> SettingsRow.Accessory {
        model.activeAction == action ? .progress : .disclosure
    }

    /// アプリのバージョン（「1.0.0（1）」）
    private static var appVersion: String {
        AppVersionText.make(bundle: .main)
    }
}

/// プレビュー用の S-15（擬似のサーバーの `one-room` のデータ）
@MainActor private func settingsPreview() -> some View {
    let toasts = DGToastCenter()
    let model = SettingsModel(
        userID: DemoScenario.myUserID,
        auth: InMemoryServer.demo(.oneRoom),
        purchases: .disabled,
        toasts: toasts,
        appleAuthorizer: DemoAppleAuthorizer()
    )
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
