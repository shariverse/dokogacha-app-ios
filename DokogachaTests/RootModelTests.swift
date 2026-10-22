//
//  RootModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 起動の流れ（`RootModel`）を擬似のサーバーで動かし、F-01 の AC（初回だけ S-01・登録後にホーム・2 回目は S-01 を出さない）と、
/// サインインの失敗・サーバー側のサインアウト・プロフィールの失敗からの戻り方を確かめる。
///
/// 画面（`RootView`）は `taskKey` が変わるたびに `follow()` を呼び直す。テストでは同じことを手で行う
/// （サインインする `follow()` は待ち、プロフィールを購読し続ける `follow()` は `Task` で動かして最後に cancel する）。
struct RootModelTests {
    /// プロフィールの購読を失敗させられる擬似の認証（それ以外は擬似のサーバーのまま）
    final class FlakyProfileAuth: AuthService {
        let server: InMemoryServer
        /// true なら、プロフィールの購読がすぐ通信エラーで終わる
        var failsProfile = true

        init(server: InMemoryServer) {
            self.server = server
        }

        var currentUserID: String? {
            server.currentUserID
        }

        func userIDChanges() -> AsyncStream<String?> {
            server.userIDChanges()
        }

        func signInAnonymously() async throws -> String {
            try await server.signInAnonymously()
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            guard failsProfile else {
                return server.profile(userID: userID)
            }
            let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<UserProfile?>.self)
            continuation.yield(.failure(AppError(.network, code: .unavailable)))
            continuation.finish()
            return stream
        }

        func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
            try await server.saveDisplayName(displayName)
        }

        var isLinkedWithApple: Bool {
            false
        }

        func linkWithApple(_ credential: AppleIDCredential) async throws -> AppleLinkOutcome {
            .linked
        }

        func signInWithLinkedAppleAccount() async throws -> String {
            throw AppError(.appleSignInFailed)
        }
    }

    /// 読めたプロフィールの後に、購読が一度だけ失敗で終わる擬似の認証（2 回目からは擬似のサーバーのまま）
    final class InterruptedProfileAuth: AuthService {
        let server: InMemoryServer
        /// プロフィールを購読した回数
        private(set) var profileSubscriptionCount = 0

        init(server: InMemoryServer) {
            self.server = server
        }

        var currentUserID: String? {
            server.currentUserID
        }

        func userIDChanges() -> AsyncStream<String?> {
            server.userIDChanges()
        }

        func signInAnonymously() async throws -> String {
            try await server.signInAnonymously()
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            profileSubscriptionCount += 1
            guard profileSubscriptionCount == 1 else {
                return server.profile(userID: userID)
            }
            // 1 回目: 読めた後に、一時的な失敗で購読が終わる
            let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<UserProfile?>.self)
            continuation.yield(.value(server.users[userID]))
            continuation.yield(.failure(AppError(.network, code: .unavailable)))
            continuation.finish()
            return stream
        }

        func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
            try await server.saveDisplayName(displayName)
        }

        var isLinkedWithApple: Bool {
            false
        }

        func linkWithApple(_ credential: AppleIDCredential) async throws -> AppleLinkOutcome {
            .linked
        }

        func signInWithLinkedAppleAccount() async throws -> String {
            throw AppError(.appleSignInFailed)
        }
    }

    /// トーストを出したままにする窓口（テストの間に消えないよう、出しておく時間を長くする）
    static func makeToasts() -> DGToastCenter {
        DGToastCenter(visibleFor: .seconds(3_600))
    }

    /// 待たずに購読し直す（固定の時間で待たない）
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }

    /// 擬似のサーバーで `start` した起動の流れ
    static func makeModel(_ server: InMemoryServer, scenario: DemoScenario) -> RootModel {
        let session = ServerSession()
        session.start(connection: .disabled(.uiTesting), services: .inMemory(server, scenario: scenario))
        return RootModel(session: session, toasts: Self.makeToasts())
    }

    /// サインインの状態に合わせて `follow()` を呼んだ後、プロフィールの購読を `Task` で動かす（画面の `.task(id:)` の代わり）
    static func startFollowing(_ model: RootModel) async -> Task<Void, Never> {
        if model.session.authState == .signedOut {
            await model.follow()
        }
        return Task { await model.follow() }
    }

    /// 初回起動: S-01 が出て、表示名を登録するとホームへ進む
    @Test
    func firstLaunchShowsOnboardingThenHomeAfterRegistering() async throws {
        let server = InMemoryServer.demo(.firstLaunch)
        let model = Self.makeModel(server, scenario: .firstLaunch)
        #expect(model.route == .loading)

        let following = await Self.startFollowing(model)
        defer { following.cancel() }
        #expect(model.session.authState == .signedIn(userID: DemoScenario.myUserID))
        #expect(await AsyncTestSupport.eventually { model.route == .onboarding })

        let onboarding = OnboardingModel(auth: model.auth, toasts: DGToastCenter(visibleFor: .seconds(3_600)))
        onboarding.displayName = "ゆい"
        await onboarding.submit()

        #expect(await AsyncTestSupport.eventually {
            if case let .home(profile) = model.route {
                return profile.displayName == "ゆい"
            }
            return false
        })
    }

    /// 2 回目の起動（表示名を登録済み）: S-01 を出さずにホームが開く
    @Test
    func registeredUserSkipsOnboarding() async throws {
        let server = InMemoryServer.demo(.empty)
        let model = Self.makeModel(server, scenario: .empty)
        let following = await Self.startFollowing(model)
        defer { following.cancel() }

        #expect(await AsyncTestSupport.eventually { model.route != .loading })
        let profile = try #require(server.users[DemoScenario.myUserID])
        #expect(model.route == .home(profile))
    }

    /// サーバー側でサインアウトされたら、匿名でサインインし直し、新しいユーザーとして S-01 から始める
    @Test
    func signsInAgainAfterServerSignOut() async throws {
        let server = InMemoryServer.demo(.empty)
        let model = Self.makeModel(server, scenario: .empty)
        let following = await Self.startFollowing(model)
        #expect(await AsyncTestSupport.eventually {
            if case .home = model.route {
                return true
            }
            return false
        })

        server.simulateSignOut()
        #expect(await AsyncTestSupport.eventually { model.session.authState == .signedOut })
        #expect(model.route == .loading)
        // 画面はサインインの状態が変わったので、前の購読を cancel して `follow()` を呼び直す
        following.cancel()
        await following.value

        let again = await Self.startFollowing(model)
        defer { again.cancel() }
        guard case let .signedIn(newUserID) = model.session.authState else {
            Issue.record("サインインし直していない: \(model.session.authState)")
            return
        }
        #expect(newUserID != DemoScenario.myUserID)
        #expect(await AsyncTestSupport.eventually { model.route == .onboarding })
    }

    /// サインインに失敗したら失敗の表示になり、再試行（ボタン・前面に戻ったとき）でサインインし直せる
    @Test
    func signInFailureCanBeRetried() async {
        let auth = ServerSessionTests.CountingAuth(result: .failure(ServerSessionTests.SignInFailure()))
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), services: ServerSessionTests.services(auth))
        let model = RootModel(session: session, toasts: Self.makeToasts())

        await model.follow()
        #expect(session.authState == .failed)
        #expect(model.route == .failed(AppError(.network)))
        #expect(model.route.failureMessage == "通信できませんでした")

        auth.result = .success("new-user")
        model.retryIfFailed()
        await model.retryTask?.value
        #expect(session.authState == .signedIn(userID: "new-user"))
        #expect(auth.signInCount == 2)
    }

    /// 失敗していないときに前面に戻っても、何もしない
    @Test
    func retryIfFailedDoesNothingWhenNotFailed() async {
        let auth = ServerSessionTests.CountingAuth(currentUserID: "existing-user")
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), services: ServerSessionTests.services(auth))
        let model = RootModel(session: session, toasts: Self.makeToasts())
        await model.follow()
        #expect(session.authState == .signedIn(userID: "existing-user"))

        model.retryIfFailed()
        #expect(model.retryTask == nil)
        #expect(model.profileAttempt == 0)
    }

    /// プロフィールを読めなかったら失敗の表示になり、再試行で購読し直せる
    @Test
    func profileFailureCanBeRetried() async throws {
        let server = InMemoryServer.demo(.empty)
        let auth = FlakyProfileAuth(server: server)
        let session = ServerSession()
        session.start(
            connection: .firebase(.emulator),
            services: DataServices(backend: .firebase, auth: auth, rooms: server, functions: server, inMemoryServer: nil)
        )
        let model = RootModel(session: session, toasts: Self.makeToasts())

        let first = await Self.startFollowing(model)
        // 失敗で購読が終わるので、`follow()` も返る
        await first.value
        #expect(model.route == .failed(AppError(.network, code: .unavailable)))

        auth.failsProfile = false
        let key = model.taskKey
        model.retryIfFailed()
        #expect(model.taskKey != key)

        let second = Task { await model.follow() }
        defer { second.cancel() }
        let profile = try #require(server.users[DemoScenario.myUserID])
        #expect(await AsyncTestSupport.eventually { model.route == .home(profile) })
    }

    /// ホームを出している間（プロフィールが読めた後）に購読が一時的に失敗しても、画面は替えずにトーストを出して購読し直す
    @Test
    func transientFailureAfterLoadKeepsHomeAndResubscribes() async throws {
        let server = InMemoryServer.demo(.empty)
        let auth = InterruptedProfileAuth(server: server)
        let session = ServerSession()
        session.start(
            connection: .firebase(.emulator),
            services: DataServices(backend: .firebase, auth: auth, rooms: server, functions: server, inMemoryServer: nil)
        )
        let toasts = Self.makeToasts()
        let model = RootModel(session: session, toasts: toasts, resubscribeDelay: Self.immediateResubscribe)
        let profile = try #require(server.users[DemoScenario.myUserID])

        let following = await Self.startFollowing(model)
        defer { following.cancel() }
        #expect(await AsyncTestSupport.eventually { auth.profileSubscriptionCount == 2 })
        #expect(model.route == .home(profile))
        #expect(toasts.current?.text == "通信できませんでした")

        // 購読し直した後も、プロフィールの変化を受け取り続ける
        server.users[DemoScenario.myUserID]?.displayName = "ゆい"
        #expect(await AsyncTestSupport.eventually {
            if case let .home(updated) = model.route {
                return updated.displayName == "ゆい"
            }
            return false
        })
    }

    /// サーバーに接続できないときは、サインインせず「接続できない」のまま（再試行もしない）
    @Test
    func unavailableServerStaysUnavailable() async {
        let session = ServerSession()
        session.start(connection: .unavailable(.missingOptionsFile("GoogleService-Info-Dev")), services: .unavailable)
        let model = RootModel(session: session, toasts: Self.makeToasts())

        await model.follow()
        #expect(session.authState == .signedOut)
        #expect(model.route == .serverUnavailable)
        model.retryIfFailed()
        #expect(model.retryTask == nil)
    }
}

extension LaunchRoute {
    /// 失敗の表示の文言（失敗でなければ nil）
    var failureMessage: String? {
        if case let .failed(error) = self {
            return error.message
        }
        return nil
    }
}
