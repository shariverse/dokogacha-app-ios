//
//  AppDelegate.swift
//  Dokogacha
//

import UIKit

/// アプリの起動時の処理（Firebase の初期化）。後のタスクで FCM・通知もここで受ける
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// サーバーへの接続とサインインの状態。`DokoGachaApp` が `@Environment` で画面に渡す
    let serverSession = ServerSession()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let connection = FirebaseBootstrap.configure(plan: FirebaseBootstrap.currentPlan())
        serverSession.start(
            connection: connection,
            authClient: connection.isFirebaseConfigured ? FirebaseAuthClient() : nil
        )
        return true
    }
}
