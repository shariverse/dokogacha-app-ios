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

    /// サインインしているアカウントが Sign in with Apple に連携済みか（S-15 の「連携済み」）
    var isLinkedWithApple: Bool { get }

    /// 匿名のアカウントを Sign in with Apple に連携する（02 の F-01「設定画面から Sign in with Apple に連携できる」）。
    ///
    /// その Apple ID が既に別のアカウントに連携されていたら（機種変更の前の端末で連携した人が、新しい端末で押した）、
    /// 連携せずに `.alreadyInUse` を返す。そのアカウントでサインインし直すかは画面で尋ね、`signInWithLinkedAppleAccount` で行う
    func linkWithApple(_ credential: AppleIDCredential) async throws -> AppleLinkOutcome

    /// 直前の `linkWithApple` が `.alreadyInUse` を返した Apple ID の、既にあるアカウントでサインインし直し、そのユーザーの ID を返す。
    ///
    /// 02 の F-01 の AC「別端末で同じ Apple ID でサインインしたときに参加ルームが復元される」ため。
    /// 今の匿名のアカウントからはサインアウトする（戻れない）。`userIDChanges` に新しいユーザーが流れ、起動の流れがホームを開き直す
    func signInWithLinkedAppleAccount() async throws -> String
}

/// Sign in with Apple で受け取った資格情報（`ASAuthorizationAppleIDCredential` から取り出した値）。
///
/// 名前とメールアドレスは要求しない（`requestedScopes = []`。プライバシーポリシーに書いた収集するデータに無いため）
nonisolated struct AppleIDCredential: Equatable, Sendable {
    /// ID トークン（JWT の文字列）
    var idToken: String
    /// 要求に使った nonce（ハッシュにする前の値。Apple には SHA-256 のハッシュを渡す）
    var rawNonce: String
}

/// Sign in with Apple の連携の結果
nonisolated enum AppleLinkOutcome: Equatable, Sendable {
    /// 今のアカウントに連携した（既に連携済みだったときも）
    case linked
    /// その Apple ID は既に別のアカウントに連携されている（今のアカウントには連携していない）
    case alreadyInUse
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
