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

    /// Unit テスト（`DokogachaTests`）のホストとして起動されたとき、XCTest が設定する環境変数。
    /// Swift Testing だけのテストでも、xcodebuild は XCTest の仕組みでホストを起動するので設定される
    static let unitTestHostEnvironmentKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    /// Unit テストのホストとして起動されたか
    let isUnitTestHost: Bool
    /// UI テストから `-uiTesting` 付きで起動されたか
    let isUITesting: Bool
    /// 撮影モード（`-screenshot-demo`）で起動されたか
    let isScreenshotDemo: Bool

    /// 起動引数と環境変数から作る
    init(arguments: [String], environment: [String: String]) {
        isUnitTestHost = Self.unitTestHostEnvironmentKeys.contains { environment[$0] != nil }
        isUITesting = arguments.contains(Self.uiTestingArgument)
        isScreenshotDemo = arguments.contains(ScreenshotDemo.argument)
    }

    /// いまのプロセスの起動のしかた
    static var current: Self {
        let process = ProcessInfo.processInfo
        return Self(arguments: process.arguments, environment: process.environment)
    }
}
