//
//  FirebaseEnvironment.swift
//  Dokogacha
//

import Foundation

/// Firebase の接続先。ビルド構成ごとに `Configs/*.xcconfig` の `DG_FIREBASE_ENVIRONMENT` で決め、Info.plist で渡す。
///
/// - Debug: `emulator`（ローカルの Emulator の demo プロジェクト）
/// - Stg: `dev`（TestFlight 用。dev プロジェクトの plist）
/// - Release: `prod`（App Store 用。prod プロジェクトの plist）
nonisolated enum FirebaseEnvironment: String, Equatable, Sendable {
    case emulator
    case dev
    case prod
}

/// Info.plist から読んだ Firebase の設定（xcconfig の値をそのまま持つ）
nonisolated struct FirebaseBuildSettings: Equatable, Sendable {
    /// 接続先を表す Info.plist のキー（値は `$(DG_FIREBASE_ENVIRONMENT)`）
    static let environmentKey = "DGFirebaseEnvironment"
    /// 読む GoogleService-Info の名前（拡張子なし）を表す Info.plist のキー（値は `$(DG_FIREBASE_OPTIONS_FILE_NAME)`）
    static let optionsFileNameKey = "DGFirebaseOptionsFileName"

    /// 接続先の文字列。キーが無いときは nil
    let environmentName: String?
    /// GoogleService-Info の名前。キーが無いときは nil
    let optionsFileName: String?

    /// 値を直接渡して作る（テスト用）
    init(environmentName: String?, optionsFileName: String?) {
        self.environmentName = environmentName
        self.optionsFileName = optionsFileName
    }

    /// Info.plist の辞書から作る
    init(infoDictionary: [String: Any]?) {
        environmentName = infoDictionary?[Self.environmentKey] as? String
        optionsFileName = infoDictionary?[Self.optionsFileNameKey] as? String
    }
}
