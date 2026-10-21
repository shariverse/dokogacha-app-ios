//
//  FirebaseAuthService.swift
//  Dokogacha
//

@preconcurrency import FirebaseAuth
import Foundation

/// Firebase Auth を使う `AuthService`。`FirebaseApp.configure` の後でだけ作る。
///
/// プロフィールの購読は Firestore（`users/{uid}`）、表示名の保存は Callable の `saveProfile` を通す
/// （`users/{uid}` はセキュリティルールで直接作れない。色と `adFree` をサーバーが決めるため）。
final class FirebaseAuthService: AuthService {
    /// Sign in with Apple の連携がまだ無い（設定画面のタスクで作る）
    enum LinkError: Error {
        case notImplemented
    }

    /// サインインの結果にユーザーが無かった（SDK が成功もエラーも返さなかった）
    enum SignInError: Error {
        case missingUser
    }

    private let gateway: any FirestoreGateway
    private let functions: any FunctionsClient

    /// Firestore と Callable の窓口を受け取って作る
    init(gateway: any FirestoreGateway, functions: any FunctionsClient) {
        self.gateway = gateway
        self.functions = functions
    }

    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    func userIDChanges() -> AsyncStream<String?> {
        let (stream, continuation) = AsyncStream.makeStream(of: String?.self, bufferingPolicy: .bufferingNewest(1))
        // SDK は登録した直後と、ユーザーが変わった・サインアウトしたときに、メインスレッドで呼ぶ
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            continuation.yield(user?.uid)
        }
        let listener = AuthStateListener(handle: handle)
        continuation.onTermination = { _ in
            Task { @MainActor in listener.remove() }
        }
        return stream
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

    /// 自分のプロフィールを購読する。
    ///
    /// キャッシュから届いた「ドキュメントが無い」は流さない（読み込み中のまま）。登録済みのユーザーがオフラインで起動し、
    /// キャッシュが空のときに S-01 を出すと、表示名を入れ直してオンラインに戻ったときに元の表示名を上書きしてしまうため。
    /// サーバーから「無い」が届いて初めて nil（未登録）を流す
    func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
        FirestoreSubscription.document(FirestorePath.user(userID), gateway: gateway, waitsForServerWhenMissing: true) { document in
            try document.map(FirestoreDecoding.userProfile)
        }
    }

    func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
        try await functions.saveProfile(SaveProfileRequest(displayName: displayName))
    }

    func linkWithApple(_ credential: AppleIDCredential) async throws {
        throw LinkError.notImplemented
    }
}

/// `addStateDidChangeListener` の札。MainActor に閉じ込めて、`onTermination` から外せるようにする
@MainActor
private final class AuthStateListener {
    private let handle: any NSObjectProtocol

    init(handle: any NSObjectProtocol) {
        self.handle = handle
    }

    func remove() {
        Auth.auth().removeStateDidChangeListener(handle)
    }
}
