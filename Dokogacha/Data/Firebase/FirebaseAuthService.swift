//
//  FirebaseAuthService.swift
//  Dokogacha
//

@preconcurrency import FirebaseAuth
import Foundation
import os

/// Firebase Auth を使う `AuthService`。`FirebaseApp.configure` の後でだけ作る。
///
/// プロフィールの購読は Firestore（`users/{uid}`）、表示名の保存は Callable の `saveProfile` を通す
/// （`users/{uid}` はセキュリティルールで直接作れない。色と `adFree` をサーバーが決めるため）。
final class FirebaseAuthService: AuthService {
    /// サインインの結果にユーザーが無かった（SDK が成功もエラーも返さなかった）
    enum SignInError: Error {
        case missingUser
    }

    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Auth")

    private let gateway: any FirestoreGateway
    private let functions: any FunctionsClient
    /// 直前の連携で「既に別のアカウントに連携されている」と返った Apple の資格情報（`signInWithLinkedAppleAccount` で使う）。
    ///
    /// Apple の ID トークンは 1 回しか使えないので、連携の失敗のエラーに入っている Firebase が作り直した資格情報
    /// （`AuthErrors.userInfoUpdatedCredentialKey`）を持っておく
    private var pendingAppleCredential: AuthCredential?

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

    var isLinkedWithApple: Bool {
        AppleAccountLink.isLinked(providerIDs: Auth.auth().currentUser?.providerData.map(\.providerID) ?? [])
    }

    func linkWithApple(_ credential: AppleIDCredential) async throws -> AppleLinkOutcome {
        guard let user = Auth.auth().currentUser else {
            throw AppError(.unauthenticated)
        }
        pendingAppleCredential = nil
        let appleCredential = OAuthProvider.appleCredential(withIDToken: credential.idToken, rawNonce: credential.rawNonce, fullName: nil)
        // SDK の結果（AuthDataResult）は Sendable でないので、コールバックの中で結果の分類だけを取り出して渡す
        // （SDK はコールバックをメインスレッドで呼ぶ。資格情報はこの MainActor のオブジェクトに残す）
        return try await withCheckedThrowingContinuation { continuation in
            user.link(with: appleCredential) { [weak self] _, error in
                guard let error else {
                    continuation.resume(returning: .linked)
                    return
                }
                let nsError = error as NSError
                switch AuthErrorCode(rawValue: nsError.code) {
                case .providerAlreadyLinked:
                    continuation.resume(returning: .linked)
                case .credentialAlreadyInUse:
                    guard let updated = nsError.userInfo[AuthErrors.userInfoUpdatedCredentialKey] as? AuthCredential else {
                        continuation.resume(throwing: AppError(.appleSignInFailed))
                        return
                    }
                    self?.pendingAppleCredential = updated
                    continuation.resume(returning: .alreadyInUse)
                default:
                    continuation.resume(throwing: Self.appError(from: nsError))
                }
            }
        }
    }

    func signInWithLinkedAppleAccount() async throws -> String {
        guard let credential = pendingAppleCredential else {
            throw AppError(.appleSignInFailed)
        }
        pendingAppleCredential = nil
        return try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let userID = result?.user.uid {
                    continuation.resume(returning: userID)
                } else if let error {
                    continuation.resume(throwing: Self.appError(from: error as NSError))
                } else {
                    continuation.resume(throwing: SignInError.missingUser)
                }
            }
        }
    }

    func deleteAccount() async throws {
        try await functions.deleteAccount()
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // キーチェーンから消せなかったときだけ失敗する。サーバーでユーザーを消してあるので、トークンが切れるとサインアウトされる
            Self.logger.error("サインアウトできない: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Firebase Auth のエラーをアプリのエラーにする（通信の失敗は「通信できませんでした」、それ以外は「Apple でサインインできませんでした」）
    nonisolated private static func appError(from error: NSError) -> AppError {
        switch AuthErrorCode(rawValue: error.code) {
        case .networkError:
            AppError(.network)
        default:
            AppError(.appleSignInFailed)
        }
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
