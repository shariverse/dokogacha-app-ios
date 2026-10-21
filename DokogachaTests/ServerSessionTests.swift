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

        func linkWithApple(_ credential: AppleIDCredential) async throws {}
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

    @Test
    func sessionSignsInWhenFirebaseIsConfigured() async {
        let auth = CountingAuth()
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), authService: auth)
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "new-user"))

        // 2 回目はサインインし直さない
        await session.signInIfNeeded()
        #expect(auth.signInCount == 1)
    }

    /// 接続できないとき・テストで初期化しないときは、SDK を呼ばない
    @Test(arguments: [
        ServerConnection.unavailable(.missingOptionsFile("GoogleService-Info-Dev")),
        .disabled(.uiTesting),
        .disabled(.unitTestHost)
    ])
    func sessionDoesNotSignInWithoutFirebase(connection: ServerConnection) async {
        let auth = CountingAuth()
        let session = ServerSession()
        session.start(connection: connection, authService: auth)
        await session.signInIfNeeded()
        #expect(session.connection == connection)
        #expect(session.authState == .signedOut)
        #expect(auth.signInCount == 0)
    }

    /// 通信エラーでも落とさず、次の呼び出しでやり直せる
    @Test
    func failedSignInCanBeRetried() async {
        let auth = CountingAuth(result: .failure(SignInFailure()))
        let session = ServerSession()
        session.start(connection: .firebase(.dev), authService: auth)
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
        session.start(connection: .firebase(.prod), authService: auth)
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
        session.start(connection: .firebase(.emulator), authService: auth)
        #expect(await AsyncTestSupport.eventually { session.authState == .signedIn(userID: "first") })
        auth.server.signedInUserID = "second"
        #expect(await AsyncTestSupport.eventually { session.authState == .signedIn(userID: "second") })
    }
}
