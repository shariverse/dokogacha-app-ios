//
//  AuthService.swift
//  Dokogacha
//

import Foundation

/// 認証とユーザーのプロフィール（F-01）の窓口。画面の Model と `ServerSession` はこの protocol だけを見る。
///
/// Firebase の実装は `FirebaseAuthService`、プレビュー・Unit テスト・`-uiTesting` では `InMemoryServer`。
protocol AuthService {
    /// サインイン済みのユーザーの ID。サインインしていなければ nil
    var currentUserID: String? { get }

    /// サインインしているユーザーの ID の変化を流す（購読を始めた時点の値も最初に流す）。
    ///
    /// サーバー側でユーザーが消された・トークンの更新に失敗してサインアウトしたときに nil が流れる。
    /// 購読をやめる（`Task` を cancel する）とリスナーを外す。
    func userIDChanges() -> AsyncStream<String?>

    /// 匿名でサインインして、ユーザーの ID を返す
    func signInAnonymously() async throws -> String

    /// 自分のプロフィール（`users/{uid}`）を購読する。まだ表示名を登録していなければ nil が流れる
    func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>>

    /// 表示名を登録・変更する（`saveProfile`。初回はユーザーを作り、アバターの色をサーバーが決める）
    func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse

    /// 匿名のアカウントを Sign in with Apple に連携する（F-01。設定画面のタスクで中身を作る。いまは口だけ）
    func linkWithApple(_ credential: AppleIDCredential) async throws
}

/// Sign in with Apple で受け取った資格情報（`ASAuthorizationAppleIDCredential` から取り出した値）
nonisolated struct AppleIDCredential: Equatable, Sendable {
    /// ID トークン（JWT の文字列）
    var idToken: String
    /// 要求に使った nonce（ハッシュにする前の値）
    var rawNonce: String
    /// 名前（初回の連携のときだけ取れる）
    var fullName: PersonNameComponents?
}

/// 匿名認証（F-01）の入口。
///
/// 既にサインインしていれば（再起動したときなど）そのユーザーを使い回し、サインインし直さない。
/// 「アプリを削除せず再起動しても同じユーザーとして扱われる」（F-01 の AC）ため。
enum AnonymousSignIn {
    /// サインイン済みのユーザーの ID を返す。まだなら匿名でサインインする
    static func ensureSignedIn(using service: any AuthService) async throws -> String {
        if let userID = service.currentUserID {
            return userID
        }
        return try await service.signInAnonymously()
    }
}
