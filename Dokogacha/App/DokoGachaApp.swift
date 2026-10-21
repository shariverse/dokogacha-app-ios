//
//  DokoGachaApp.swift
//  Dokogacha
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

/// アプリの入口。Firebase の初期化は `AppDelegate` で行い、画面が出たら匿名でサインインする
@main
struct DokoGachaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(appDelegate.serverSession)
                // 画面の寿命に合わせてサインインする（接続できないとき・テストでは何もしない）
                .task {
                    await appDelegate.serverSession.signInIfNeeded()
                }
        }
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            ContentView()
        }
    }
}
