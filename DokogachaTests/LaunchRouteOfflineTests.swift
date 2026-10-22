//
//  LaunchRouteOfflineTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// オフラインの起動の流れ（02 の §9）: キャッシュが空で起動中から進まない（PR #40）・オフラインでサインインに失敗した後に
/// 回線が戻ったらやり直す（PR #17）を確かめる
struct LaunchRouteOfflineTests {
    /// オフラインでサインインに失敗した・プロフィールがキャッシュに無く読み込み中のままなら、起動中ではなく「オフライン」にする（PR #40）
    @Test
    func launchRouteShowsOfflineInsteadOfLoading() {
        let loading = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "me"),
            profile: .loading(userID: "me"),
            reachability: .offline
        )
        #expect(loading == .offline)
        let failed = LaunchRoute.resolve(connection: .firebase(.emulator), authState: .failed, profile: .idle, reachability: .offline)
        #expect(failed == .offline)
        // サインインの途中（オフラインならすぐ失敗する）は起動中のまま
        let signingIn = LaunchRoute.resolve(connection: .firebase(.emulator), authState: .signingIn, profile: .idle, reachability: .offline)
        #expect(signingIn == .loading)
        // オンライン・分からないときは今までどおり
        let online = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "me"),
            profile: .loading(userID: "me"),
            reachability: .online
        )
        #expect(online == .loading)
    }

    /// 読めた画面（S-01・ホーム）は、オフラインでもキャッシュの値でそのまま出す
    @Test
    func launchRouteKeepsLoadedScreensOffline() {
        let home = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "me"),
            profile: .loaded(userID: "me", profile: LaunchRouteTests.profile),
            reachability: .offline
        )
        #expect(home == .home(LaunchRouteTests.profile))
        let onboarding = LaunchRoute.resolve(
            connection: .firebase(.emulator),
            authState: .signedIn(userID: "me"),
            profile: .loaded(userID: "me", profile: nil),
            reachability: .offline
        )
        #expect(onboarding == .onboarding)
    }

    /// オフラインで初回のサインインに失敗したら「オフライン」を出し、回線が戻ったらやり直してサインインする（PR #17）
    @Test
    func signInRetriesWhenBackOnline() async {
        let monitor = NetworkOfflineTests.ControlledNetworkPathMonitor()
        let network = NetworkStatus()
        network.start(monitor: monitor)
        monitor.continuation.yield(.unsatisfied)
        #expect(await AsyncTestSupport.eventually { network.isOffline })

        let auth = ServerSessionTests.CountingAuth(result: .failure(ServerSessionTests.SignInFailure()))
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), services: ServerSessionTests.services(auth))
        let model = RootModel(session: session, toasts: RootModelTests.makeToasts(), network: network)
        await model.follow()
        #expect(model.route == .offline)
        // オフラインのまま前面に戻っても、やり直さない（また失敗するだけ）
        model.retryIfFailed()
        #expect(model.retryTask == nil)

        auth.result = .success("new-user")
        monitor.continuation.yield(.satisfied)
        #expect(await AsyncTestSupport.eventually { network.reachability == .online })
        #expect(model.route == .failed(AppError(.network)))
        // 画面（`RootView`）は回線が戻ったら `retryIfFailed()` を呼ぶ
        model.retryIfFailed()
        await model.retryTask?.value
        #expect(session.authState == .signedIn(userID: "new-user"))
        monitor.continuation.finish()
    }
}
