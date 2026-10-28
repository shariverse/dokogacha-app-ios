//
//  FirebaseCollectionPolicyTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// Analytics・Crashlytics に送るのが Stg・Release のアプリだけで、Debug・Emulator・テスト・撮影モードでは送らないことを確かめる
struct FirebaseCollectionPolicyTests {
    /// 普通にアプリを起動したとき
    private static let normalLaunch = LaunchContext(arguments: ["Dokogacha"], environment: [:])
    /// Stg・Release の Info.plist の値（`DG_FIREBASE_COLLECTION_ENABLED = YES`）
    private static let collecting = FirebaseCollectionSettings(analyticsEnabled: true, crashlyticsEnabled: true)
    /// Debug の Info.plist の値（`DG_FIREBASE_COLLECTION_ENABLED = NO`）
    private static let notCollecting = FirebaseCollectionSettings(analyticsEnabled: false, crashlyticsEnabled: false)

    /// Stg（dev）・Release（prod）に繋いだアプリは、構成の設定どおり送る
    @Test(arguments: [FirebaseEnvironment.dev, .prod])
    func stgAndReleaseCollect(environment: FirebaseEnvironment) {
        let policy = FirebaseCollectionPolicy.make(
            launch: Self.normalLaunch,
            connection: .firebase(environment),
            settings: Self.collecting
        )
        #expect(policy == FirebaseCollectionPolicy(analytics: true, crashlytics: true))
    }

    /// Debug（Emulator に接続）は、構成の設定を取り違えて YES にしても送らない
    @Test
    func emulatorNeverCollects() {
        let policy = FirebaseCollectionPolicy.make(
            launch: Self.normalLaunch,
            connection: .firebase(.emulator),
            settings: Self.collecting
        )
        #expect(policy == .disabled)
    }

    /// 構成の設定が NO なら、dev・prod に繋いでも送らない
    @Test
    func buildSettingOffDisablesCollection() {
        let policy = FirebaseCollectionPolicy.make(
            launch: Self.normalLaunch,
            connection: .firebase(.prod),
            settings: Self.notCollecting
        )
        #expect(policy == .disabled)
    }

    /// Analytics と Crashlytics は、それぞれのキーの値で決まる
    @Test
    func eachSDKFollowsItsOwnKey() {
        let policy = FirebaseCollectionPolicy.make(
            launch: Self.normalLaunch,
            connection: .firebase(.dev),
            settings: FirebaseCollectionSettings(analyticsEnabled: false, crashlyticsEnabled: true)
        )
        #expect(policy == FirebaseCollectionPolicy(analytics: false, crashlytics: true))
    }

    /// Unit テストのホスト・`-uiTesting`・撮影モードは、Stg・Release の構成で起動しても送らない
    @Test(arguments: [
        LaunchContext(arguments: ["Dokogacha"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]),
        LaunchContext(arguments: ["Dokogacha", LaunchContext.uiTestingArgument], environment: [:]),
        LaunchContext(arguments: ["Dokogacha", ScreenshotDemo.argument], environment: [:])
    ])
    func testsAndScreenshotsNeverCollect(launch: LaunchContext) {
        let policy = FirebaseCollectionPolicy.make(launch: launch, connection: .firebase(.prod), settings: Self.collecting)
        #expect(policy == .disabled)
    }

    /// Firebase を初期化していない・接続できないときは送らない
    @Test(arguments: [
        ServerConnection.notStarted,
        .disabled(.uiTesting),
        .unavailable(.missingOptionsFile("GoogleService-Info-Prod"))
    ])
    func unconfiguredNeverCollects(connection: ServerConnection) {
        let policy = FirebaseCollectionPolicy.make(launch: Self.normalLaunch, connection: connection, settings: Self.collecting)
        #expect(policy == .disabled)
    }

    /// Info.plist の値は、xcconfig から入る文字列（YES・NO）も、plist の真偽値も読み、無い・読めない値は送らない側に倒す
    @Test
    func readsInfoPlistFlags() {
        #expect(FirebaseCollectionSettings.flag("YES"))
        #expect(FirebaseCollectionSettings.flag("true"))
        #expect(FirebaseCollectionSettings.flag(true))
        #expect(!FirebaseCollectionSettings.flag("NO"))
        #expect(!FirebaseCollectionSettings.flag(""))
        #expect(!FirebaseCollectionSettings.flag("$(DG_FIREBASE_COLLECTION_ENABLED)"))
        #expect(!FirebaseCollectionSettings.flag(nil))
        #expect(!FirebaseCollectionSettings.flag(false))
    }

    /// このテストのホスト（Debug でビルドしたアプリ）の Info.plist には、xcconfig の NO が SDK のキーで入っている
    @Test
    func debugInfoPlistDisablesCollection() {
        let info = Bundle.main.infoDictionary
        #expect(info?[FirebaseCollectionSettings.analyticsKey] as? String == "NO")
        #expect(info?[FirebaseCollectionSettings.crashlyticsKey] as? String == "NO")
        let settings = FirebaseCollectionSettings(infoDictionary: info)
        #expect(settings == FirebaseCollectionSettings(analyticsEnabled: false, crashlyticsEnabled: false))
    }
}
