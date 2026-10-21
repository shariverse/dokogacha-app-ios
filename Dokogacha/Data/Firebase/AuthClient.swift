//
//  AuthClient.swift
//  Dokogacha
//

@preconcurrency import FirebaseAuth
import Foundation

/// 認証の SDK（Firebase Auth）の窓口。テストでは擬似の実装に差し替える
protocol AuthClient {
    /// サインイン済みのユーザーの ID。サインインしていなければ nil
    var currentUserID: String? { get }
    /// 匿名でサインインして、ユーザーの ID を返す
    func signInAnonymously() async throws -> String
}

/// 匿名認証（F-01）の入口。
///
/// 既にサインインしていれば（再起動したときなど）そのユーザーを使い回し、サインインし直さない。
/// 「アプリを削除せず再起動しても同じユーザーとして扱われる」（F-01 の AC）ため。
enum AnonymousSignIn {
    /// サインイン済みのユーザーの ID を返す。まだなら匿名でサインインする
    static func ensureSignedIn(using client: any AuthClient) async throws -> String {
        if let userID = client.currentUserID {
            return userID
        }
        return try await client.signInAnonymously()
    }
}

/// Firebase Auth を使う `AuthClient`。`FirebaseApp.configure` の後でだけ作る
struct FirebaseAuthClient: AuthClient {
    /// サインインの結果にユーザーが無かった（SDK が成功もエラーも返さなかった）
    enum SignInError: Error {
        case missingUser
    }

    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    func signInAnonymously() async throws -> String {
        // SDK の結果（AuthDataResult）は Sendable でないので、コールバックの中で ID だけを取り出して渡す
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let userID = result?.user.uid {
                    continuation.resume(returning: userID)
                } else {
                    continuation.resume(throwing: error ?? SignInError.missingUser)
                }
            }
        }
    }
}
