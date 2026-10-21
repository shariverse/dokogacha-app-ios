//
//  AppDelegate.swift
//  Dokogacha
//

import UIKit

/// アプリの起動時の処理（Firebase の初期化と、データ層の実装の選択）。後のタスクで FCM・通知もここで受ける
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// サーバーへの接続とサインインの状態。`DokoGachaApp` が `@Environment` で画面に渡す
    let serverSession = ServerSession()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let connection = FirebaseBootstrap.configure(plan: FirebaseBootstrap.currentPlan())
        // Firebase を初期化したら Firebase の実装、テスト・撮影なら擬似のサーバー（`-demo-scenario` のデータ）を使う
        serverSession.start(connection: connection, services: DataServices.make(connection: connection, launch: .current))
        return true
    }
}
