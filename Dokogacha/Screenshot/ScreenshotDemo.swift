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
        case createRoom
        case invite
        case settings
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

extension ScreenshotDemo {
    /// S-03 ルーム作成を擬似のサーバーで開く（ホームから進まずに、S-03 だけを `NavigationStack` に入れて出す）。
    ///
    /// 起動引数 `-screenshot-room-name <名前>` でルーム名を入れ、`-screenshot-unlock-rule <UnlockRule の rawValue>` で
    /// 解禁の条件を選んだ状態で開く（締切日時のピッカーを出した状態を撮るため）
    struct CreateRoomScene: View {
        /// ルーム名の起動引数
        static let roomNameArgument = "-screenshot-room-name"
        /// 解禁の条件の起動引数
        static let unlockRuleArgument = "-screenshot-unlock-rule"

        @State private var toasts: DGToastCenter
        private let model: CreateRoomModel

        /// - Parameter functions: `createRoom` を呼ぶ窓口（撮影モードでは擬似のサーバー）
        init(functions: any FunctionsClient) {
            let toasts = DGToastCenter()
            let model = CreateRoomModel(functions: functions, toasts: toasts)
            if let name = ScreenshotDemo.value(after: Self.roomNameArgument) {
                model.name = name
            }
            if let rule = ScreenshotDemo.value(after: Self.unlockRuleArgument).flatMap(UnlockRule.init(rawValue:)) {
                model.unlockRule = rule
            }
            self.model = model
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                CreateRoomView(model: model) { _ in }
            }
            .dgToast(toasts)
        }
    }

    /// S-04 招待を、デモのルーム（「年末の旅行」・招待コード `DK7-29Q`）で開く
    struct InviteScene: View {
        @State private var toasts = DGToastCenter()

        var body: some View {
            NavigationStack {
                if let code = InviteCode(DemoScenario.inviteCode) {
                    InviteView(
                        model: InviteModel(
                            destination: InviteDestination(roomID: DemoScenario.roomID, roomName: "年末の旅行", inviteCode: code),
                            toasts: toasts
                        )
                    ) {}
                }
            }
            .dgToast(toasts)
        }
    }

    /// S-15 設定を擬似のサーバーで開く（ホームから進まずに、設定の画面を根元にして出す）
    struct SettingsScene: View {
        @State private var toasts: DGToastCenter
        private let model: SettingsModel

        /// - Parameter auth: プロフィールの窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(auth: any AuthService) {
            let toasts = DGToastCenter()
            model = SettingsModel(userID: auth.currentUserID ?? DemoScenario.myUserID, auth: auth, toasts: toasts)
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                SettingsView(model: model, toasts: toasts)
            }
            .dgToast(toasts)
        }
    }

    /// 起動引数で `name` の次に渡された値（無ければ nil）
    static func value(after name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
