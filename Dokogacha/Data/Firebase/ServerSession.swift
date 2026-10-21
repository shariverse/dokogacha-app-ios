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
        /// サインインしていない（接続できないとき・サーバー側でサインアウトされたとき）
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
    /// 匿名認証の状態。`start` の後は、Auth の変化（サーバー側でのサインアウトなど）に追随する
    private(set) var authState: AuthState = .signedOut

    @ObservationIgnored private var authService: (any AuthService)?
    @ObservationIgnored private var authObservation: Task<Void, Never>?

    /// 起動時に一度だけ、初期化の結果と認証の窓口を受け取り、Auth の変化の購読を始める。
    ///
    /// Firebase を初期化できなかったときは、サインインも購読もしない
    func start(connection: ServerConnection, authService: (any AuthService)?) {
        self.connection = connection
        authObservation?.cancel()
        self.authService = connection.isFirebaseConfigured ? authService : nil
        guard let authService = self.authService else {
            return
        }
        let changes = authService.userIDChanges()
        authObservation = Task { [weak self] in
            for await userID in changes {
                self?.applyAuthChange(userID: userID)
            }
        }
    }

    deinit {
        authObservation?.cancel()
    }

    /// 匿名でサインインする（既にサインイン済みならそのユーザーを使う）。接続できないとき・サインイン済みのときは何もしない
    func signInIfNeeded() async {
        guard let authService else {
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
            let userID = try await AnonymousSignIn.ensureSignedIn(using: authService)
            authState = .signedIn(userID: userID)
        } catch {
            authState = .failed
        }
    }

    /// Auth の変化を状態に映す。
    ///
    /// - ユーザーがいれば `.signedIn`（別のユーザーに変わったときも）
    /// - いなくなったら（サーバー側でユーザーが消えた・トークンを更新できずサインアウトした）、サインイン済みだったときだけ `.signedOut`。
    ///   サインインの途中（購読を始めた直後に届く「まだいない」）と失敗の表示は変えない
    private func applyAuthChange(userID: String?) {
        if let userID {
            authState = .signedIn(userID: userID)
        } else if case .signedIn = authState {
            authState = .signedOut
        }
    }
}
