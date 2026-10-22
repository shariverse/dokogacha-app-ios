//
//  AppDelegate.swift
//  Dokogacha
//

import UIKit

/// アプリの起動時の処理（Firebase の初期化と、データ層の実装の選択）。後のタスクで FCM・通知もここで受ける
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// サーバーへの接続とサインインの状態。`DokoGachaApp` が `@Environment` で画面に渡す
    let serverSession = ServerSession()
    /// 招待リンクで開かれたときの行き先。`DokoGachaApp` が URL を渡し、`RootView` が画面に渡す
    let deepLinks = DeepLinkRouter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let launch = LaunchContext.current
        let connection = FirebaseBootstrap.configure(plan: FirebaseBootstrap.currentPlan())
        // Firebase を初期化したら Firebase の実装、テスト・撮影なら擬似のサーバー（`-demo-scenario` のデータ）を使う
        serverSession.start(connection: connection, services: DataServices.make(connection: connection, launch: launch))
        // UI テスト・撮影モードでは、起動引数の URL で招待リンクから開かれたことにする（Simulator では Universal Links で開けないため）
        if let url = launch.openURL {
            deepLinks.handle(url)
        }
        return true
    }
}
