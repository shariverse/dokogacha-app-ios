//
//  ServerSessionTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 匿名認証の入口（F-01）が、サインイン済みなら使い回し、まだなら匿名でサインインすることを確かめる
struct ServerSessionTests {
    /// 呼ばれた回数を数える擬似の認証
    final class FakeAuthClient: AuthClient {
        var currentUserID: String?
        var result: Result<String, any Error>
        private(set) var signInCount = 0

        init(currentUserID: String? = nil, result: Result<String, any Error> = .success("new-user")) {
            self.currentUserID = currentUserID
            self.result = result
        }

        func signInAnonymously() async throws -> String {
            signInCount += 1
            let userID = try result.get()
            currentUserID = userID
            return userID
        }
    }

    struct SignInFailure: Error {}

    @Test
    func signsInAnonymouslyWhenSignedOut() async throws {
        let client = FakeAuthClient()
        let userID = try await AnonymousSignIn.ensureSignedIn(using: client)
        #expect(userID == "new-user")
        #expect(client.signInCount == 1)
    }

    /// 再起動したとき（サインイン済み）は、サインインし直さずに同じユーザーを使う
    @Test
    func reusesSignedInUser() async throws {
        let client = FakeAuthClient(currentUserID: "existing-user")
        let userID = try await AnonymousSignIn.ensureSignedIn(using: client)
        #expect(userID == "existing-user")
        #expect(client.signInCount == 0)
    }

    @Test
    func sessionSignsInWhenFirebaseIsConfigured() async {
        let client = FakeAuthClient()
        let session = ServerSession()
        session.start(connection: .firebase(.emulator), authClient: client)
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "new-user"))

        // 2 回目はサインインし直さない
        await session.signInIfNeeded()
        #expect(client.signInCount == 1)
    }

    /// 接続できないとき・テストで初期化しないときは、SDK を呼ばない
    @Test(arguments: [
        ServerConnection.unavailable(.missingOptionsFile("GoogleService-Info-Dev")),
        .disabled(.uiTesting),
        .disabled(.unitTestHost)
    ])
    func sessionDoesNotSignInWithoutFirebase(connection: ServerConnection) async {
        let client = FakeAuthClient()
        let session = ServerSession()
        session.start(connection: connection, authClient: client)
        await session.signInIfNeeded()
        #expect(session.connection == connection)
        #expect(session.authState == .signedOut)
        #expect(client.signInCount == 0)
    }

    /// 通信エラーでも落とさず、次の呼び出しでやり直せる
    @Test
    func failedSignInCanBeRetried() async {
        let client = FakeAuthClient(result: .failure(SignInFailure()))
        let session = ServerSession()
        session.start(connection: .firebase(.dev), authClient: client)
        await session.signInIfNeeded()
        #expect(session.authState == .failed)

        client.result = .success("retried-user")
        await session.signInIfNeeded()
        #expect(session.authState == .signedIn(userID: "retried-user"))
        #expect(client.signInCount == 2)
    }
}
