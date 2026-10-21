//
//  DokoGachaApp.swift
//  Dokogacha
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

/// アプリの入口。Firebase の初期化は `AppDelegate` で行い、サインインと最初の画面の選択は `RootView`（起動の流れ）が行う
@main
struct DokoGachaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(appDelegate.serverSession)
        }
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            RootView(session: appDelegate.serverSession)
        case .onboarding:
            ScreenshotDemo.OnboardingScene(auth: appDelegate.serverSession.services.auth)
        case .createRoom:
            ScreenshotDemo.CreateRoomScene(functions: appDelegate.serverSession.services.functions)
        case .invite:
            ScreenshotDemo.InviteScene()
        }
    }
}
