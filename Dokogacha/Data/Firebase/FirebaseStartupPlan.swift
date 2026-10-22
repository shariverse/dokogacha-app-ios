//
//  FirebaseStartupPlan.swift
//  Dokogacha
//

import Foundation

/// 起動時に Firebase をどう初期化するか。SDK に触る前に、起動のしかたと Info.plist の設定だけから決める。
///
/// 判定を SDK から切り出して純粋な関数にし、構成ごとの接続先・テストで初期化しないことを Swift Testing で確かめる。
nonisolated enum FirebaseStartupPlan: Equatable, Sendable {
    /// Firebase を初期化しない（テスト・撮影モード）
    case skip(ServerConnection.DisabledReason)
    /// コードで作った `FirebaseOptions` で Emulator の demo プロジェクトに接続する
    case connectToEmulator
    /// GoogleService-Info（`path`）を読んで、`environment` のプロジェクトに接続する
    case loadOptionsFile(path: String, environment: FirebaseEnvironment)
    /// 設定が足りないので初期化しない
    case unavailable(ServerConnection.UnavailableReason)

    /// 起動のしかたと Info.plist の設定から、初期化のしかたを決める。
    ///
    /// - Parameters:
    ///   - launch: 起動のしかた。テストのホスト・UI テスト・撮影モードでは初期化しない
    ///   - settings: Info.plist の Firebase の設定
    ///   - optionsFilePath: GoogleService-Info の名前（拡張子なし）から、アプリの中のパスを返す。無ければ nil
    static func make(
        launch: LaunchContext,
        settings: FirebaseBuildSettings,
        optionsFilePath: (String) -> String?
    ) -> Self {
        if launch.isUnitTestHost {
            return .skip(.unitTestHost)
        }
        if launch.isUITesting {
            return .skip(.uiTesting)
        }
        if launch.isScreenshotDemo {
            return .skip(.screenshotDemo)
        }
        guard let name = settings.environmentName, let environment = FirebaseEnvironment(rawValue: name) else {
            return .unavailable(.unknownEnvironment(settings.environmentName))
        }
        switch environment {
        case .emulator:
            return .connectToEmulator
        case .dev, .prod:
            guard let fileName = settings.optionsFileName, !fileName.isEmpty, let path = optionsFilePath(fileName) else {
                return .unavailable(.missingOptionsFile(settings.optionsFileName))
            }
            return .loadOptionsFile(path: path, environment: environment)
        }
    }
}

/// GoogleService-Info（またはコードで作った設定）が、SDK に渡してよい値か。
///
/// 値が欠けている・API キーの形が違うまま `FirebaseApp.configure` すると、SDK（FirebaseCore・Installations）が
/// 例外で落とす。plist が壊れていてもアプリを落とさないよう、渡す前にここで確かめる。
nonisolated enum FirebaseOptionsValidation {
    /// Firebase Installations が求める API キーの長さ
    static let apiKeyLength = 39
    /// Firebase Installations が求める API キーの先頭の文字
    static let apiKeyPrefix = "A"

    /// Auth・Firestore・Functions・Installations に要る値がそろっていて、API キーの形が正しいか
    static func isValid(googleAppID: String?, gcmSenderID: String?, projectID: String?, apiKey: String?) -> Bool {
        let required = [googleAppID, gcmSenderID, projectID, apiKey]
        guard required.allSatisfy({ !($0 ?? "").isEmpty }), let apiKey else {
            return false
        }
        return apiKey.count == apiKeyLength && apiKey.hasPrefix(apiKeyPrefix)
    }
}
