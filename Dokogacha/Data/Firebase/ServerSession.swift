//
//  ServerSession.swift
//  Dokogacha
//

import Foundation
import Observation

/// サーバーへの接続と、サインインしているユーザーと、データ層の窓口。アプリ全体で 1 つを `@Environment` で共有する。
///
/// 画面は `connection` で「サーバーに接続できない」表示にするかを決め、`services` の protocol（`RoomRepository` など）を
/// 画面の Model に渡す。Firebase の実装か擬似のサーバーかは、起動時に `DataServices.make` が決める。
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

    /// 起動時に決まった接続の状態。`start` を呼ぶまでは `.notStarted`
    private(set) var connection: ServerConnection = .notStarted
    /// 匿名認証の状態。`start` の後は、Auth の変化（サーバー側でのサインアウトなど）に追随する
    private(set) var authState: AuthState = .signedOut
    /// データ層の窓口（`start` の前は、どの操作も「通信できませんでした」になる窓口）
    private(set) var services: DataServices = .unavailable

    @ObservationIgnored private var authService: (any AuthService)?
    @ObservationIgnored private var authObservation: Task<Void, Never>?

    /// 起動時に一度だけ、初期化の結果とデータ層の窓口を受け取り、Auth の変化の購読を始める。
    ///
    /// サインインを許さない窓口（接続できないとき）では、サインインも購読もしない
    func start(connection: ServerConnection, services: DataServices) {
        self.connection = connection
        self.services = services
        authObservation?.cancel()
        authService = services.allowsSignIn ? services.auth : nil
        guard let authService else {
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
