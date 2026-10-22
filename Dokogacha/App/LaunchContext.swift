//
//  LaunchContext.swift
//  Dokogacha
//

import Foundation

/// アプリがどう起動されたか（テストのホストか・UI テストか・撮影モードか）。
///
/// 起動引数と環境変数だけから決める値の型にして、Firebase を初期化するかどうかの判定をテストできるようにする。
nonisolated struct LaunchContext: Equatable, Sendable {
    /// UI テストが渡す起動引数。メモリ上の擬似のサーバーで動かし、Firebase を初期化しない
    static let uiTestingArgument = "-uiTesting"

    /// UI テスト・撮影モードで、招待リンクで開かれたことにする起動引数（`-open-url <URL>`）。
    /// Simulator では Universal Links でアプリを開けない（AASA を取りに行けない）ので、起動の直後に `DeepLinkRouter` へ渡す
    static let openURLArgument = "-open-url"

    /// UI テスト・撮影モードで、通知から開かれたことにする起動引数（`-open-notification <ペイロードの JSON>`。
    /// 例: `{"roomId":"demo-room","target":"room"}`）。擬似のサーバーでは通知が届かないので、起動の直後に `DeepLinkRouter` へ渡す
    static let openNotificationArgument = "-open-notification"

    /// UI テストで、ほかのメンバーの参加・準備OK・引き直しの賛成を擬似のサーバーが自動で返す起動引数（`InMemoryAutoMembers`）。
    /// UI テストは 1 台の端末しか操作できないので、06 の §2 の通しのシナリオで使う。`-uiTesting` のときだけ効く
    static let autoMembersArgument = "-ui-auto-members"

    /// Unit テスト（`DokogachaTests`）のホストとして起動されたとき、XCTest が設定する環境変数。
    /// Swift Testing だけのテストでも、xcodebuild は XCTest の仕組みでホストを起動するので設定される
    static let unitTestHostEnvironmentKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    /// Unit テストのホストとして起動されたか
    let isUnitTestHost: Bool
    /// UI テストから `-uiTesting` 付きで起動されたか
    let isUITesting: Bool
    /// 撮影モード（`-screenshot-demo`）で起動されたか
    let isScreenshotDemo: Bool
    /// 擬似のサーバーに入れるデモのデータ（`-demo-scenario <名前>`。`-uiTesting`・撮影モードのときに使う。
    /// 指定が無ければ、撮影モードでは `DemoScenario.screenshotFallback`、それ以外では `DemoScenario.fallback`）
    let demoScenario: DemoScenario
    /// 起動の直後に開いたことにする URL（`-open-url <URL>`）。`-uiTesting`・撮影モードのときだけ読み、ほかは nil
    let openURL: URL?
    /// 起動の直後に開いたことにする通知のペイロード（`-open-notification <JSON>`）。`-uiTesting`・撮影モードのときだけ読み、ほかは nil
    let openNotification: [String: String]?
    /// ほかのメンバーの操作を擬似のサーバーが自動で返すか（`-ui-auto-members`。`-uiTesting` のときだけ true になりうる）
    let autoMembers: Bool

    /// 起動引数と環境変数から作る
    init(arguments: [String], environment: [String: String]) {
        isUnitTestHost = Self.unitTestHostEnvironmentKeys.contains { environment[$0] != nil }
        isUITesting = arguments.contains(Self.uiTestingArgument)
        isScreenshotDemo = arguments.contains(ScreenshotDemo.argument)
        autoMembers = isUITesting && arguments.contains(Self.autoMembersArgument)
        // 撮影モード（App Store の画面）は、シナリオを指定しなければルームが並んだ状態で撮る
        demoScenario = DemoScenario.from(
            arguments: arguments,
            fallback: isScreenshotDemo ? DemoScenario.screenshotFallback : DemoScenario.fallback
        )
        if isUITesting || isScreenshotDemo {
            openURL = Self.value(after: Self.openURLArgument, in: arguments).flatMap { URL(string: $0) }
            openNotification = Self.value(after: Self.openNotificationArgument, in: arguments).flatMap(Self.payload(fromJSON:))
        } else {
            openURL = nil
            openNotification = nil
        }
    }

    /// 起動引数で `name` の次にある値（無ければ nil）
    private static func value(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    /// JSON のオブジェクト（値はすべて文字列）を読む。読めなければ nil
    private static func payload(fromJSON json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    }

    /// いまのプロセスの起動のしかた
    static var current: Self {
        let process = ProcessInfo.processInfo
        return Self(arguments: process.arguments, environment: process.environment)
    }
}
