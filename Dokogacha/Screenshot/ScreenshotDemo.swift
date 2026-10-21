//
//  ScreenshotDemo.swift
//  Dokogacha
//
//  App Store 用スクリーンショットの撮影モード。
//  Tools/capture_screenshots.sh が次の起動引数でアプリを起動し、目的の画面をデモデータで開かせる。
//
//    -screenshot-demo -screenshot-scene <Scene の rawValue> -AppleLanguages (<言語>) -AppleLocale <ロケール>
//
//  画面を足すときは、Scene に case を足し、App/DokoGachaApp.swift の rootView で開く画面を返し、
//  AppStore/screenshots.json の scenes に同じ rawValue を足す（突き合わせは Tools/app_store_config.py が行う）。
//  デモデータは実データと混ざらないよう、撮影モードのときだけメモリ上やインメモリのストアに用意する。
//

import SwiftUI

enum ScreenshotDemo {
    /// 撮る画面。rawValue が AppStore/screenshots.json の scene と対応する
    enum Scene: String {
        case home
        case onboarding
    }

    /// 撮影モードで起動するときの起動引数（`LaunchContext` からも読むので nonisolated）
    nonisolated static let argument = "-screenshot-demo"

    /// 撮影モードで起動しているか
    static let isEnabled = ProcessInfo.processInfo.arguments.contains(argument)

    /// 撮影モードで開く画面。撮影モードでないときと、知らない値を渡されたときは nil
    static let scene: Scene? = {
        guard isEnabled else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot-scene"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Scene(rawValue: arguments[index + 1])
    }()
}

extension ScreenshotDemo {
    /// S-01 オンボーディングを擬似のサーバーで開く（起動の流れを通さず、`-demo-scenario` によらずに S-01 を出す）。
    ///
    /// 起動引数 `-screenshot-display-name <名前>` を付けると、入力欄にその名前を入れた状態で開く（入力した状態・無効の状態を撮るため）
    struct OnboardingScene: View {
        /// 入力欄に入れておく名前の起動引数
        static let displayNameArgument = "-screenshot-display-name"

        @State private var toasts = DGToastCenter()
        private let model: OnboardingModel

        /// - Parameter auth: 表示名を登録する窓口（撮影モードでは擬似のサーバー）
        init(auth: any AuthService) {
            let toasts = DGToastCenter()
            let model = OnboardingModel(auth: auth, toasts: toasts)
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: Self.displayNameArgument), arguments.indices.contains(index + 1) {
                model.displayName = arguments[index + 1]
            }
            self.model = model
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            OnboardingView(model: model)
                .dgToast(toasts)
        }
    }
}
