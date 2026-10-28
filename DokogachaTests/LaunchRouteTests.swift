//
//  LaunchRouteTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 起動の流れの判定（初回だけ S-01・2 回目からはホーム・失敗と接続できないときの表示）を確かめる（F-01）
struct LaunchRouteTests {
    static let profile = UserProfile(
        displayName: "ゆい",
        avatarColor: AvatarPalette.colors[0],
        adFree: false,
        fcmTokens: [],
        createdAt: Date(timeIntervalSince1970: 0)
    )

    /// 初回起動（表示名が無い）は S-01
    @Test
    func firstLaunchShowsOnboarding() {
        let route = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "me"),
            profile: .loaded(userID: "me", profile: nil)
        )
        #expect(route == .onboarding)
    }

    /// 表示名を登録した後（2 回目の起動を含む）は、S-01 を出さずにホーム
    @Test
    func registeredUserGoesHome() {
        let route = LaunchRoute.resolve(
            connection: .firebase(.prod),
            authState: .signedIn(userID: "me"),
            profile: .loaded(userID: "me", profile: Self.profile)
        )
        #expect(route == .home(Self.profile))
    }

    /// サインインの途中・プロフィールを読んでいる途中は、S-01 もホームも出さない（初回の画面がちらつかない）
    @Test
    func showsLoadingWhileSigningInOrLoading() {
        let cases: [(ServerSession.AuthState, ProfileLoadState)] = [
            (.signedOut, .idle),
            (.signingIn, .idle),
            (.signedIn(userID: "me"), .idle),
            (.signedIn(userID: "me"), .loading(userID: "me"))
        ]
        for (authState, profile) in cases {
            let route = LaunchRoute.resolve(connection: .firebase(.emulator), authState: authState, profile: profile)
            #expect(route == .loading, "\(authState) / \(profile)")
        }
    }

    /// 前のユーザーのプロフィールで画面を決めない（サーバー側でサインアウトされ、別のユーザーでサインインし直した直後）
    @Test
    func ignoresProfileOfAnotherUser() {
        let loaded = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "new"),
            profile: .loaded(userID: "old", profile: Self.profile)
        )
        #expect(loaded == .loading)
        let failed = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "new"),
            profile: .failed(userID: "old", error: AppError(.network))
        )
        #expect(failed == .loading)
    }

    /// サインインに失敗したら、再試行できる失敗の表示（「通信できませんでした」）
    @Test
    func signInFailureShowsFailed() {
        let route = LaunchRoute.resolve(connection: .firebase(.dev), authState: .failed, profile: .idle)
        #expect(route == .failed(AppError(.network)))
    }

    /// プロフィールを読めなかったら、その理由で失敗の表示
    @Test
    func profileFailureShowsFailed() {
        let error = AppError(.permissionDenied, code: .permissionDenied)
        let route = LaunchRoute.resolve(
            connection: .firebase(.dev),
            authState: .signedIn(userID: "me"),
            profile: .failed(userID: "me", error: error)
        )
        #expect(route == .failed(error))
    }

    /// サーバーに接続できない（plist が無い）ときは、サインインの状態によらず「接続できない」
    @Test
    func unavailableConnectionShowsServerUnavailable() {
        let authStates: [ServerSession.AuthState] = [.signedOut, .failed, .signedIn(userID: "me")]
        for authState in authStates {
            let route = LaunchRoute.resolve(
                connection: .unavailable(.missingOptionsFile("GoogleService-Info-Dev")),
                authState: authState,
                profile: .loaded(userID: "me", profile: Self.profile)
            )
            #expect(route == .serverUnavailable, "\(authState)")
        }
    }

    /// 起動の処理の前は読み込み中
    @Test
    func notStartedShowsLoading() {
        let route = LaunchRoute.resolve(connection: .notStarted, authState: .signedOut, profile: .idle)
        #expect(route == .loading)
    }

    /// テスト・撮影のための擬似のサーバーでも、同じ判定で S-01 を出す
    @Test
    func inMemoryServerUsesSameRule() {
        let route = LaunchRoute.resolve(
            connection: .disabled(.uiTesting),
            authState: .signedIn(userID: DemoScenario.myUserID),
            profile: .loaded(userID: DemoScenario.myUserID, profile: nil)
        )
        #expect(route == .onboarding)
    }
}
