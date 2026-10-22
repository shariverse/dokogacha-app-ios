//
//  FirebaseTelemetry.swift
//  Dokogacha
//

@preconcurrency import FirebaseAnalytics
@preconcurrency import FirebaseCrashlytics
import Foundation

/// Analytics と Crashlytics の収集を、起動ごとに `FirebaseCollectionPolicy` の値にそろえる（この 2 つの SDK の設定に触るのはここだけ）。
///
/// どちらの SDK も、コードで渡した値を端末に覚えて Info.plist の既定より優先する。前の起動で送る設定にした端末でも
/// （同じ端末に Stg を入れた後に Debug を入れたなど）送らないよう、送るときも送らないときも毎回渡し直す。
enum FirebaseTelemetry {
    /// `FirebaseBootstrap.configure` の後に呼ぶ。Firebase を初期化していなければ何もしない
    /// （どちらの SDK も初期化の前は動かないので、Unit テストのホスト・`-uiTesting`・撮影モードでは何も送らない）
    /// - Parameters:
    ///   - connection: 起動時の接続の状態
    ///   - launch: 起動のしかた
    ///   - bundle: 収集の設定を読む Info.plist のバンドル
    static func start(connection: ServerConnection, launch: LaunchContext, bundle: Bundle = .main) {
        guard connection.isFirebaseConfigured else {
            return
        }
        let policy = FirebaseCollectionPolicy.make(
            launch: launch,
            connection: connection,
            settings: FirebaseCollectionSettings(infoDictionary: bundle.infoDictionary)
        )
        Analytics.setAnalyticsCollectionEnabled(policy.analytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(policy.crashlytics)
    }
}
