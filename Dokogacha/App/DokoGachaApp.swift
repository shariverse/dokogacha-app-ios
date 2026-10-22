//
//  DokoGachaApp.swift
//  Dokogacha
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

/// アプリの入口。Firebase の初期化は `AppDelegate` で行い、サインインと最初の画面の選択は `RootView`（起動の流れ）が行う。
///
/// 招待リンク（Universal Links）は、SwiftUI の `onOpenURL` と `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` の
/// どちらで届いても `DeepLinkRouter` に渡す（同じ URL が両方に届いても、覚えるコードは同じなので開くのは 1 回）
@main
struct DokoGachaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(appDelegate.serverSession)
                .environment(appDelegate.push)
                .environment(appDelegate.ads)
                .environment(appDelegate.purchases)
                .onOpenURL { url in
                    appDelegate.deepLinks.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    appDelegate.deepLinks.handle(activity)
                }
        }
    }

    /// 撮影モード（ScreenshotDemo）のときは、撮る画面を開く
    @ViewBuilder private var rootView: some View {
        switch ScreenshotDemo.scene {
        case .home, nil:
            RootView(session: appDelegate.serverSession, deepLinks: appDelegate.deepLinks)
        case .onboarding:
            ScreenshotDemo.OnboardingScene(auth: appDelegate.serverSession.services.auth)
        case .createRoom:
            ScreenshotDemo.CreateRoomScene(functions: appDelegate.serverSession.services.functions)
        case .invite:
            ScreenshotDemo.InviteScene()
        case .settings:
            ScreenshotDemo.SettingsScene(services: appDelegate.serverSession.services)
        case .room:
            ScreenshotDemo.RoomScene(services: appDelegate.serverSession.services)
        case .candidateDetail:
            ScreenshotDemo.CandidateDetailScene(services: appDelegate.serverSession.services)
        case .addCandidate:
            ScreenshotDemo.AddCandidateScene(services: appDelegate.serverSession.services)
        case .members:
            ScreenshotDemo.MembersScene(services: appDelegate.serverSession.services)
        case .roomSettings:
            ScreenshotDemo.RoomSettingsScene(services: appDelegate.serverSession.services)
        case .gacha:
            ScreenshotDemo.GachaScene(services: appDelegate.serverSession.services)
        case .result:
            ScreenshotDemo.ResultScene(services: appDelegate.serverSession.services)
        case .resultMember:
            ScreenshotDemo.ResultMemberScene(services: appDelegate.serverSession.services)
        case .homeMemories:
            ScreenshotDemo.HomeMemoriesScene(session: appDelegate.serverSession, deepLinks: appDelegate.deepLinks)
        case .pastIdeas:
            ScreenshotDemo.PastIdeasScene(services: appDelegate.serverSession.services)
        case .inviteLastMembers:
            ScreenshotDemo.InviteLastMembersScene(services: appDelegate.serverSession.services)
        case .roomAdFree:
            ScreenshotDemo.RoomAdFreeScene(services: appDelegate.serverSession.services)
        case .settingsAppleLinked:
            ScreenshotDemo.SettingsScene(services: appDelegate.serverSession.services, appleLinked: true)
        case .settingsAdFree:
            ScreenshotDemo.SettingsScene(services: appDelegate.serverSession.services, adFree: true)
        case .settingsDeleteAccount:
            ScreenshotDemo.SettingsScene(services: appDelegate.serverSession.services, confirmingDeletion: true)
        case .licenses:
            NavigationStack {
                LicensesView()
            }
        }
    }
}
