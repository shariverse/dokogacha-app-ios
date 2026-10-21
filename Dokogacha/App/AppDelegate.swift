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
        let authService: (any AuthService)? = if connection.isFirebaseConfigured {
            FirebaseAuthService(
                gateway: FirebaseFirestoreGateway(),
                functions: CallableFunctionsClient(transport: FirebaseCallableTransport())
            )
        } else {
            nil
        }
        serverSession.start(connection: connection, authService: authService)
        return true
    }
}
