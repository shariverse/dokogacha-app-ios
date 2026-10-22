//
//  FirebaseCollectionPolicy.swift
//  Dokogacha
//

import Foundation

/// Analytics と Crashlytics にデータを送るか（診断データ・利用状況の収集）。
///
/// 送るのは TestFlight（Stg）と App Store（Release）のアプリだけにする。Debug（Emulator に接続）・Unit テストのホスト・
/// `-uiTesting`・撮影モードでは送らない（開発中の操作やテストのクラッシュで、dev・prod の計測を汚さないため）。
/// 構成ごとの既定は xcconfig の `DG_FIREBASE_COLLECTION_ENABLED` を Info.plist の SDK のキー
/// （`FIREBASE_ANALYTICS_COLLECTION_ENABLED`・`FirebaseCrashlyticsCollectionEnabled`）で渡し、
/// 起動のしかたと接続先はここで重ねて確かめる（SDK のキーは初回の起動の既定で、実際の値は起動ごとに SDK へ渡し直す）。
///
/// SDK に触る前の値だけから決める純粋な関数にして、Swift Testing で確かめる。
nonisolated struct FirebaseCollectionPolicy: Equatable, Sendable {
    /// Analytics のイベントを送るか
    let analytics: Bool
    /// Crashlytics のクラッシュの記録を送るか
    let crashlytics: Bool

    /// どちらも送らない
    static let disabled = Self(analytics: false, crashlytics: false)

    /// 起動のしかた・接続先・構成の設定から決める。
    ///
    /// - Parameters:
    ///   - launch: 起動のしかた。Unit テストのホスト・`-uiTesting`・撮影モードでは送らない
    ///   - connection: Firebase への接続の状態。dev・prod に繋いだときだけ送る（Emulator・未接続では送らない）
    ///   - settings: Info.plist の収集の設定（構成ごと）
    static func make(launch: LaunchContext, connection: ServerConnection, settings: FirebaseCollectionSettings) -> Self {
        guard !launch.isUnitTestHost, !launch.isUITesting, !launch.isScreenshotDemo else {
            return .disabled
        }
        switch connection {
        case .firebase(.dev), .firebase(.prod):
            return Self(analytics: settings.analyticsEnabled, crashlytics: settings.crashlyticsEnabled)
        case .firebase(.emulator), .disabled, .unavailable, .notStarted:
            return .disabled
        }
    }
}

/// Info.plist の収集の設定（SDK が読むキーと同じもの。値は xcconfig の `DG_FIREBASE_COLLECTION_ENABLED`）
nonisolated struct FirebaseCollectionSettings: Equatable, Sendable {
    /// Firebase Analytics が初回の起動の既定として読むキー
    static let analyticsKey = "FIREBASE_ANALYTICS_COLLECTION_ENABLED"
    /// Crashlytics が初回の起動の既定として読むキー
    static let crashlyticsKey = "FirebaseCrashlyticsCollectionEnabled"

    /// Analytics を送ってよい構成か
    let analyticsEnabled: Bool
    /// Crashlytics を送ってよい構成か
    let crashlyticsEnabled: Bool

    /// 値を直接渡して作る（テスト用）
    init(analyticsEnabled: Bool, crashlyticsEnabled: Bool) {
        self.analyticsEnabled = analyticsEnabled
        self.crashlyticsEnabled = crashlyticsEnabled
    }

    /// Info.plist の辞書から作る。キーが無い・読めない値なら送らない側に倒す
    init(infoDictionary: [String: Any]?) {
        analyticsEnabled = Self.flag(infoDictionary?[Self.analyticsKey])
        crashlyticsEnabled = Self.flag(infoDictionary?[Self.crashlyticsKey])
    }

    /// Info.plist の真偽値を読む。xcconfig の変数で入れた値は文字列（`YES`・`NO`）になるので、文字列も読む
    /// （SDK も文字列を `boolValue` で読む）。それ以外・無いときは false
    static func flag(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            value
        case let value as String:
            ["yes", "true", "1"].contains(value.lowercased())
        default:
            false
        }
    }
}
