//
//  ServerSession.swift
//  Dokogacha
//

import Foundation
import Observation

/// サーバーへの接続と、サインインしているユーザー。アプリ全体で 1 つを `@Environment` で共有する。
///
/// 後続のデータ層・画面は `connection` を見て、Firebase を使えるか・「サーバーに接続できない」表示にするかを決める。
@Observable
final class ServerSession {
    /// 匿名認証の状態
    enum AuthState: Equatable {
        /// まだサインインしていない（接続できないときもこのまま）
        case signedOut
        /// サインインしている途中
        case signingIn
        /// サインインした（値はユーザーの ID）
        case signedIn(userID: String)
        /// サインインに失敗した（通信エラーなど）
        case failed
    }

    /// 起動時に決まった接続の状態。`start` を呼ぶまでは「初期化していない」扱い
    private(set) var connection: ServerConnection = .unavailable(.unknownEnvironment(nil))
    /// 匿名認証の状態
    private(set) var authState: AuthState = .signedOut

    @ObservationIgnored private var authClient: (any AuthClient)?

    /// 起動時に一度だけ、初期化の結果と認証の窓口を受け取る。接続できないときは `authClient` に nil を渡す
    func start(connection: ServerConnection, authClient: (any AuthClient)?) {
        self.connection = connection
        self.authClient = connection.isFirebaseConfigured ? authClient : nil
    }

    /// 匿名でサインインする（既にサインイン済みならそのユーザーを使う）。接続できないとき・サインイン済みのときは何もしない
    func signInIfNeeded() async {
        guard let authClient else {
            return
        }
        switch authState {
        case .signingIn, .signedIn:
            return
        case .signedOut, .failed:
            break
        }
        authState = .signingIn
        do {
            let userID = try await AnonymousSignIn.ensureSignedIn(using: authClient)
            authState = .signedIn(userID: userID)
        } catch {
            authState = .failed
        }
    }
}
