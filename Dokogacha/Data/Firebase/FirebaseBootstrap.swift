//
//  FirebaseBootstrap.swift
//  Dokogacha
//

@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions
import Foundation
import os

/// `FirebaseStartupPlan` に従って Firebase の SDK を初期化する（SDK に触るのはここだけ）。
enum FirebaseBootstrap {
    private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Firebase")

    /// いまのプロセスの起動のしかたと `Bundle.main` の Info.plist から初期化のしかたを決める
    static func currentPlan(bundle: Bundle = .main) -> FirebaseStartupPlan {
        FirebaseStartupPlan.make(
            launch: .current,
            settings: FirebaseBuildSettings(infoDictionary: bundle.infoDictionary),
            optionsFilePath: { bundle.path(forResource: $0, ofType: "plist") }
        )
    }

    /// 初期化して、接続の状態を返す。設定が足りない・読めないときは落とさずに `.unavailable` を返す
    static func configure(plan: FirebaseStartupPlan) -> ServerConnection {
        switch plan {
        case let .skip(reason):
            return .disabled(reason)
        case let .unavailable(reason):
            logger.error("Firebase を初期化しない（サーバーに接続できない状態で起動する）: \(String(describing: reason), privacy: .public)")
            return .unavailable(reason)
        case .connectToEmulator:
            configureApp(options: emulatorOptions())
            connectToEmulator()
            return .firebase(.emulator)
        case let .loadOptionsFile(path, environment):
            // 必須の値が欠けたまま configure すると SDK が例外で落とすので、先に確かめる
            guard let options = FirebaseOptions(contentsOfFile: path), hasRequiredValues(options) else {
                logger.error("GoogleService-Info を読めない: \(path, privacy: .public)")
                return .unavailable(.invalidOptionsFile(path))
            }
            configureApp(options: options)
            return .firebase(environment)
        }
    }

    /// Cloud Functions の呼び出し口（東京リージョン）。Emulator への接続は `configure` で済ませてある
    static func functions() -> Functions {
        Functions.functions(region: FirebaseConstants.functionsRegion)
    }

    /// SDK に渡してよい値か（`FirebaseOptionsValidation`）
    private static func hasRequiredValues(_ options: FirebaseOptions) -> Bool {
        FirebaseOptionsValidation.isValid(
            googleAppID: options.googleAppID,
            gcmSenderID: options.gcmSenderID,
            projectID: options.projectID,
            apiKey: options.apiKey
        )
    }

    /// 2 回目の呼び出し（SwiftUI の Preview など）で例外にならないよう、初期化済みなら何もしない
    private static func configureApp(options: FirebaseOptions) {
        guard FirebaseApp.app() == nil else {
            return
        }
        FirebaseApp.configure(options: options)
    }

    /// Emulator の demo プロジェクトの設定。plist を使わずにコードで作る
    private static func emulatorOptions() -> FirebaseOptions {
        let options = FirebaseOptions(googleAppID: FirebaseEmulator.googleAppID, gcmSenderID: FirebaseEmulator.gcmSenderID)
        options.projectID = FirebaseEmulator.projectID
        options.apiKey = FirebaseEmulator.apiKey
        options.bundleID = Bundle.main.bundleIdentifier ?? ""
        return options
    }

    /// Auth・Firestore・Functions を Emulator に向ける。どれも最初に使う前に呼ぶ必要がある
    private static func connectToEmulator() {
        Auth.auth().useEmulator(withHost: FirebaseEmulator.host, port: FirebaseEmulator.authPort)
        Firestore.firestore().useEmulator(withHost: FirebaseEmulator.host, port: FirebaseEmulator.firestorePort)
        functions().useEmulator(withHost: FirebaseEmulator.host, port: FirebaseEmulator.functionsPort)
    }
}
