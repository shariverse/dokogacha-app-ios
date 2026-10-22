//
//  ServerSessionTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 匿名認証の入口（F-01）と、認証の状態が Auth の変化に追随することを確かめる
struct ServerSessionTests {
    struct SignInFailure: Error {}

    /// 呼ばれた回数を数え、サインインの結果を決められる擬似の認証（擬似のサーバーの上に作る）
    final class CountingAuth: AuthService {
        let server = InMemoryServer()
        var result: Result<String, any Error>
        private(set) var signInCount = 0

        init(currentUserID: String? = nil, result: Result<String, any Error> = .success("new-user")) {
            server.signedInUserID = currentUserID
            self.result = result
        }

        var currentUserID: String? {
            server.signedInUserID
        }

        func userIDChanges() -> AsyncStream<String?> {
            server.userIDChanges()
        }

        func signInAnonymously() async throws -> String {
            signInCount += 1
            let userID = try result.get()
            server.signedInUserID = userID
            return userID
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            server.profile(userID: userID)
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

        func deleteAccount() async throws {
            try await server.deleteAccount()
        }

        func signOut() {
            server.signOut()
        }
    }

    /// サインインを、テストが `finishSignIn` を呼ぶまで止めておく擬似の認証
    final class SuspendedAuth: AuthService {
        let server = InMemoryServer()
        private(set) var signInCount = 0
        private var pending: CheckedContinuation<String, Never>?

        /// サインインの途中で止まっているか
        var isWaiting: Bool {
            pending != nil
        }

        var currentUserID: String? {
            server.signedInUserID
        }

        func userIDChanges() -> AsyncStream<String?> {
            server.userIDChanges()
        }

        func signInAnonymously() async throws -> String {
            signInCount += 1
            let userID = await withCheckedContinuation { pending = $0 }
            server.signedInUserID = userID
            return userID
        }

        /// 止めていたサインインを `userID` で終える
        func finishSignIn(_ userID: String) {
            pending?.resume(returning: userID)
            pending = nil
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            server.profile(userID: userID)
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

        func deleteAccount() async throws {
            try await server.deleteAccount()
        }

        func signOut() {
            server.signOut()
        }
    }

    /// ユーザーの ID の変化を、テストが 1 件ずつ手で流す擬似の認証。
    ///
    /// 購読している側が次の値を取りに来た回数（`pullCount`）を数える。取りに来たら、その前に流した値は処理し終わっている
    /// （`ServerSession` は 1 件ずつ MainActor で処理してから次を取りに来る）ので、時間で待たずに「処理した後」を確かめられる
    final class ManualStreamAuth: AuthService {
        let server = InMemoryServer()
        var currentUserID: String?
        /// 購読している側が次の値を取りに来た回数
        private(set) var pullCount = 0
        private var waiting: CheckedContinuation<String??, Never>?

        func userIDChanges() -> AsyncStream<String?> {
            AsyncStream(unfolding: { [weak self] in
                guard let self else {
                    return nil
                }
                return await pull()
            })
        }

        /// 次の値を待つ（`send` か `finish` で返る）
        private func pull() async -> String?? {
            pullCount += 1
            return await withCheckedContinuation { waiting = $0 }
        }

        /// 購読している側に値を 1 件流す（取りに来ている間だけ呼ぶ）
        func send(_ userID: String?) {
            waiting?.resume(returning: .some(userID))
            waiting = nil
        }

        /// 購読を終える
        func finish() {
            waiting?.resume(returning: nil)
            waiting = nil
        }

        func signInAnonymously() async throws -> String {
            currentUserID = "new-user"
            return "new-user"
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            server.profile(userID: userID)
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

        func deleteAccount() async throws {
            try await server.deleteAccount()
        }

        func signOut() {
            server.signOut()
        }
    }

    /// 擬似の認証を使う窓口
    static func services(_ auth: CountingAuth) -> DataServices {
        DataServices(backend: .firebase, auth: auth, rooms: auth.server, functions: auth.server, inMemoryServer: nil)
    }

    @Test
    func signsInAnonymouslyWhenSignedOut() async throws {
        let auth = CountingAuth()
        let userID = try await AnonymousSignIn.ensureSignedIn(using: auth)
        #expect(userID == "new-user")
        #expect(auth.signInCount == 1)
    }

    /// 再起動したとき（サインイン済み）は、サインインし直さずに同じユーザーを使う
    @Test
    func reusesSignedInUser() async throws {
        let auth = CountingAuth(currentUserID: "existing-user")
        let userID = try await AnonymousSignIn.ensureSignedIn(using: auth)
        #expect(userID == "existing-user")
        #expect(auth.signInCount == 0)
    }

    /// `start` の前は「未初期化」で、設定漏れ（unavailable）と区別できる
    @Test
    func connectionIsNotStartedBeforeStart() {
        let session = ServerSession()
        #expect(session.connection == .notStarted)
        #expect(session.services.backend == .unavailable)
    }

    @Test
    func sessionSignsInWhenFirebaseIsConfigured() async {
        let auth = CountingAuth()
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), services: Self.services(auth))
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "new-user"))

        // 2 回目はサインインし直さない
        await session.signInIfNeeded()
        #expect(auth.signInCount == 1)
    }

    /// サインインの途中で呼ばれた 2 回目は、サインインし直さずに、進行中のサインインの完了を待って返る
    @Test
    func secondCallWaitsForSignInInProgress() async {
        let auth = SuspendedAuth()
        let session = ServerSession()
        session.start(
            connection: .firebase(.emulator),
            services: DataServices(backend: .firebase, auth: auth, rooms: auth.server, functions: auth.server, inMemoryServer: nil)
        )
        let first = Task { await session.signInIfNeeded() }
        #expect(await AsyncTestSupport.eventually { auth.isWaiting })
        #expect(session.authState == .signingIn)

        let second = Task {
            await session.signInIfNeeded()
            return session.authState
        }
        // 2 回目を、進行中のサインインを待つところまで進める（時間では待たず、順番を譲る）
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(session.authState == .signingIn)

        auth.finishSignIn("new-user")
        // 2 回目は完了を待ったので、返った時点でサインイン済みになっている
        #expect(await second.value == .signedIn(userID: "new-user"))
        await first.value
        #expect(auth.signInCount == 1)
    }

    /// 接続できないときは、サインインしない
    @Test
    func sessionDoesNotSignInWhenUnavailable() async {
        let session = ServerSession()
        let connection = ServerConnection.unavailable(.missingOptionsFile("GoogleService-Info-Dev"))
        session.start(connection: connection, services: .unavailable)
        await session.signInIfNeeded()
        #expect(session.connection == connection)
        #expect(session.authState == .signedOut)
    }

    /// テスト・UI テストでは、擬似のサーバーでサインインする（Firebase の SDK は呼ばない）
    @Test
    func sessionSignsInToInMemoryServer() async {
        let server = InMemoryServer.demo(.empty)
        let session = ServerSession()
        session.start(connection: .disabled(.uiTesting), services: .inMemory(server, scenario: .empty))
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: DemoScenario.myUserID))
    }

    /// 通信エラーでも落とさず、次の呼び出しでやり直せる
    @Test
    func failedSignInCanBeRetried() async {
        let auth = CountingAuth(result: .failure(SignInFailure()))
        let session = ServerSession()
        session.start(connection: .firebase(.dev), services: Self.services(auth))
        await session.signInIfNeeded()
        #expect(session.authState == .failed)

        auth.result = .success("retried-user")
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "retried-user"))
        #expect(auth.signInCount == 2)
    }

    /// サーバー側でサインアウトされた（ユーザーが消えた・トークンを更新できなかった）ら、`.signedOut` に戻る
    @Test
    func followsSignOutOnServer() async {
        let auth = CountingAuth(currentUserID: "existing-user")
        let session = ServerSession()
        session.start(connection: .firebase(.prod), services: Self.services(auth))
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "existing-user"))

        auth.server.simulateSignOut()
        #expect(await AsyncTestSupport.eventually { session.authState == .signedOut })

        // サインインし直せる
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "new-user"))
    }

    /// 別のユーザーに変わったら、そのユーザーに追随する
    @Test
    func followsUserChange() async {
        let auth = CountingAuth(currentUserID: "first")
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), services: Self.services(auth))
        #expect(await AsyncTestSupport.eventually { session.authState == .signedIn(userID: "first") })
        auth.server.signedInUserID = "second"
        #expect(await AsyncTestSupport.eventually { session.authState == .signedIn(userID: "second") })
    }

    /// 購読を始めた直後の「まだいない」が、サインインの完了より後に届いても、`.signedIn` のままにする
    /// （今の Auth にユーザーがいれば古い通知として無視する分岐）
    @Test
    func staleSignedOutNotificationAfterSignInIsIgnored() async {
        let auth = ManualStreamAuth()
        let session = ServerSession()
        session.start(
            connection: .firebase(.emulator),
            services: DataServices(backend: .firebase, auth: auth, rooms: auth.server, functions: auth.server, inMemoryServer: nil)
        )
        // 購読が最初の値を取りに来るのを待つ（まだ何も流さない）
        #expect(await AsyncTestSupport.eventually { auth.pullCount == 1 })

        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "new-user"))

        // サインインより前の時点の「まだいない」が遅れて届く
        auth.send(nil)
        // 次の値を取りに来た = 流した nil を処理し終わった
        #expect(await AsyncTestSupport.eventually { auth.pullCount == 2 })
        #expect(session.authState == .signedIn(userID: "new-user"))

        // 今の Auth にもユーザーがいなくなってからの nil は、サインアウトとして映す（無視する分岐と区別できている）
        auth.currentUserID = nil
        auth.send(nil)
        #expect(await AsyncTestSupport.eventually { session.authState == .signedOut })
        auth.finish()
    }
}
