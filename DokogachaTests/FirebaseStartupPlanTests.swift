//
//  FirebaseStartupPlanTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 起動のしかたと構成ごとの設定から、Firebase の初期化のしかた（接続先・初期化しないこと）が決まることを確かめる
struct FirebaseStartupPlanTests {
    /// 普通にアプリを起動したとき（テストでも撮影でもない）
    private static let normalLaunch = LaunchContext(arguments: ["Dokogacha"], environment: [:])

    /// Debug の Info.plist の値
    private static let debugSettings = FirebaseBuildSettings(environmentName: "emulator", optionsFileName: "")
    /// Stg の Info.plist の値
    private static let stgSettings = FirebaseBuildSettings(environmentName: "dev", optionsFileName: "GoogleService-Info-Dev")
    /// Release の Info.plist の値
    private static let releaseSettings = FirebaseBuildSettings(environmentName: "prod", optionsFileName: "GoogleService-Info-Prod")

    /// アプリに入っている plist を名前から探す擬似の関数
    private static func bundle(containing names: Set<String>) -> (String) -> String? {
        { names.contains($0) ? "/app/\($0).plist" : nil }
    }

    @Test
    func debugConnectsToEmulatorWithoutOptionsFile() {
        let plan = FirebaseStartupPlan.make(
            launch: Self.normalLaunch,
            settings: Self.debugSettings,
            optionsFilePath: Self.bundle(containing: [])
        )
        #expect(plan == .connectToEmulator)
    }

    @Test
    func stgLoadsDevOptionsFile() {
        let plan = FirebaseStartupPlan.make(
            launch: Self.normalLaunch,
            settings: Self.stgSettings,
            optionsFilePath: Self.bundle(containing: ["GoogleService-Info-Dev", "GoogleService-Info-Prod"])
        )
        #expect(plan == .loadOptionsFile(path: "/app/GoogleService-Info-Dev.plist", environment: .dev))
    }

    @Test
    func releaseLoadsProdOptionsFile() {
        let plan = FirebaseStartupPlan.make(
            launch: Self.normalLaunch,
            settings: Self.releaseSettings,
            optionsFilePath: Self.bundle(containing: ["GoogleService-Info-Dev", "GoogleService-Info-Prod"])
        )
        #expect(plan == .loadOptionsFile(path: "/app/GoogleService-Info-Prod.plist", environment: .prod))
    }

    /// plist が無い（Secrets 未登録・Fork の PR）ときは落とさずに「接続できない」にする
    @Test
    func missingOptionsFileIsUnavailable() {
        let plan = FirebaseStartupPlan.make(
            launch: Self.normalLaunch,
            settings: Self.releaseSettings,
            optionsFilePath: Self.bundle(containing: [])
        )
        #expect(plan == .unavailable(.missingOptionsFile("GoogleService-Info-Prod")))
    }

    /// Release に dev の plist だけが入っていても、dev には接続しない
    @Test
    func releaseDoesNotFallBackToDevOptionsFile() {
        let plan = FirebaseStartupPlan.make(
            launch: Self.normalLaunch,
            settings: Self.releaseSettings,
            optionsFilePath: Self.bundle(containing: ["GoogleService-Info-Dev"])
        )
        #expect(plan == .unavailable(.missingOptionsFile("GoogleService-Info-Prod")))
    }

    @Test
    func emptyOptionsFileNameIsUnavailable() {
        let settings = FirebaseBuildSettings(environmentName: "dev", optionsFileName: "")
        let plan = FirebaseStartupPlan.make(launch: Self.normalLaunch, settings: settings, optionsFilePath: { _ in "/app/x.plist" })
        #expect(plan == .unavailable(.missingOptionsFile("")))
    }

    /// xcconfig の設定漏れ（`$(…)` が空・知らない値・キーが無い）は「接続できない」にする
    @Test(arguments: [nil, "", "staging"] as [String?])
    func unknownEnvironmentIsUnavailable(environmentName: String?) {
        let settings = FirebaseBuildSettings(environmentName: environmentName, optionsFileName: "GoogleService-Info-Dev")
        let plan = FirebaseStartupPlan.make(launch: Self.normalLaunch, settings: settings, optionsFilePath: { _ in "/app/x.plist" })
        #expect(plan == .unavailable(.unknownEnvironment(environmentName)))
    }

    /// Unit テストのホストでは、どの構成でも初期化しない
    @Test
    func unitTestHostSkipsFirebase() {
        let launch = LaunchContext(arguments: ["Dokogacha"], environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        let plan = FirebaseStartupPlan.make(launch: launch, settings: Self.debugSettings, optionsFilePath: Self.bundle(containing: []))
        #expect(plan == .skip(.unitTestHost))
    }

    /// UI テスト（`-uiTesting`）では、どの構成でも初期化しない
    @Test
    func uiTestingSkipsFirebase() {
        let launch = LaunchContext(arguments: ["Dokogacha", "-uiTesting"], environment: [:])
        let plan = FirebaseStartupPlan.make(
            launch: launch,
            settings: Self.stgSettings,
            optionsFilePath: Self.bundle(containing: ["GoogleService-Info-Dev"])
        )
        #expect(plan == .skip(.uiTesting))
    }

    /// 撮影モードでは、デモデータで撮るので初期化しない
    @Test
    func screenshotDemoSkipsFirebase() {
        let launch = LaunchContext(arguments: ["Dokogacha", "-screenshot-demo", "-screenshot-scene", "home"], environment: [:])
        let plan = FirebaseStartupPlan.make(launch: launch, settings: Self.debugSettings, optionsFilePath: Self.bundle(containing: []))
        #expect(plan == .skip(.screenshotDemo))
    }

    /// このテストのホスト（Debug でビルドしたアプリ）の Info.plist に、xcconfig の値が入っていること
    @Test
    func debugInfoPlistSelectsEmulator() {
        let settings = FirebaseBuildSettings(infoDictionary: Bundle.main.infoDictionary)
        #expect(settings.environmentName == FirebaseEnvironment.emulator.rawValue)
        #expect(settings.optionsFileName?.isEmpty == true)
    }

    /// このテストのプロセスは Unit テストのホストとして判定される（Firebase を初期化していない）
    @Test
    func currentProcessIsUnitTestHost() {
        #expect(LaunchContext.current.isUnitTestHost)
        #expect(FirebaseBootstrap.currentPlan() == .skip(.unitTestHost))
    }

    @Test
    func skipPlanIsDisabledConnection() {
        #expect(FirebaseBootstrap.configure(plan: .skip(.uiTesting)) == .disabled(.uiTesting))
        #expect(FirebaseBootstrap.configure(plan: .unavailable(.missingOptionsFile("x"))) == .unavailable(.missingOptionsFile("x")))
    }

    /// Emulator の demo プロジェクトの設定は、SDK が確かめる形（API キーは A で始まる 39 文字）を満たす
    @Test
    func emulatorOptionsAreValid() {
        #expect(FirebaseOptionsValidation.isValid(
            googleAppID: FirebaseEmulator.googleAppID,
            gcmSenderID: FirebaseEmulator.gcmSenderID,
            projectID: FirebaseEmulator.projectID,
            apiKey: FirebaseEmulator.apiKey
        ))
    }

    /// SDK に渡す設定の値（テストの引数）
    nonisolated struct OptionsValues: Sendable {
        var googleAppID: String? = "1:123:ios:0"
        var gcmSenderID: String? = "123"
        var projectID: String? = "demo-x"
        var apiKey: String? = FirebaseEmulator.apiKey
    }

    /// 値が欠けている・API キーの形が違う設定
    nonisolated static let invalidOptionsValues = [
        OptionsValues(googleAppID: ""),
        OptionsValues(gcmSenderID: nil),
        OptionsValues(projectID: ""),
        OptionsValues(apiKey: nil),
        OptionsValues(apiKey: "demo-api-key"),
        OptionsValues(apiKey: "B" + String(repeating: "x", count: 38))
    ]

    /// 値が欠けている・API キーの形が違う設定は SDK に渡さない
    @Test(arguments: invalidOptionsValues)
    func invalidOptionsAreRejected(values: OptionsValues) {
        #expect(!FirebaseOptionsValidation.isValid(
            googleAppID: values.googleAppID,
            gcmSenderID: values.gcmSenderID,
            projectID: values.projectID,
            apiKey: values.apiKey
        ))
    }

    /// 読めない plist の中身。plist でないもの・必須の値（GOOGLE_APP_ID など）が欠けたもの
    nonisolated static let invalidOptionsFileContents = [
        "not a plist",
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>PROJECT_ID</key><string>demo-x</string></dict></plist>
        """
    ]

    /// 読めない plist は、SDK に渡さず（例外で落とさず）「接続できない」にする
    @Test(arguments: invalidOptionsFileContents)
    func invalidOptionsFileIsUnavailable(contents: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID().uuidString).plist")
        try Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let connection = FirebaseBootstrap.configure(plan: .loadOptionsFile(path: url.path, environment: .dev))
        #expect(connection == .unavailable(.invalidOptionsFile(url.path)))
    }
}
