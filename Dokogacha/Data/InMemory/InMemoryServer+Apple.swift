//
//  InMemoryServer+Apple.swift
//  Dokogacha
//

import Foundation

/// Sign in with Apple の連携（02 の §1 F-01）を、Firebase Auth の代わりにメモリ上で行う。
///
/// 擬似のサーバーでは ID トークンをそのまま Apple のアカウントの目印として扱う（署名と nonce は確かめない）。
/// 1 つの Apple のアカウントは 1 つのユーザーにだけ連携でき、別のユーザーが連携しようとすると `.alreadyInUse` を返す（Firebase の `credentialAlreadyInUse`）
extension InMemoryServer {
    var isLinkedWithApple: Bool {
        guard let signedInUserID else {
            return false
        }
        return appleAccounts.values.contains(signedInUserID)
    }

    func linkWithApple(_ credential: AppleIDCredential) async throws -> AppleLinkOutcome {
        pendingAppleAccount = nil
        guard let signedInUserID else {
            throw AppError(.unauthenticated)
        }
        switch appleAccounts[credential.idToken] {
        case nil:
            // Firebase と同じく、1 つのユーザーに Apple のアカウントは 1 つまで（別の Apple ID に付け替えない）
            if isLinkedWithApple {
                return .linked
            }
            appleAccounts[credential.idToken] = signedInUserID
            return .linked
        case signedInUserID:
            return .linked
        default:
            pendingAppleAccount = credential.idToken
            return .alreadyInUse
        }
    }

    func signInWithLinkedAppleAccount() async throws -> String {
        guard let account = pendingAppleAccount, let userID = appleAccounts[account] else {
            throw AppError(.appleSignInFailed)
        }
        pendingAppleAccount = nil
        signedInUserID = userID
        return userID
    }

    /// Sign in with Apple のトークンを取り消す（擬似のサーバーでは、受け取った authorization code を記録するだけ）
    func revokeAppleToken(authorizationCode: String) async throws {
        guard signedInUserID != nil else {
            throw Self.error(.unauthenticated)
        }
        revokedAppleAuthorizationCodes.append(authorizationCode)
    }
}

/// 擬似のサーバーでの Sign in with Apple の認証（Apple の認証の画面を出さずに、決まった ID トークンを返す）。
///
/// `-uiTesting`・撮影モード・プレビューで使う（Simulator の Apple の認証の画面はテストで操作できず、Emulator も Apple の ID トークンを確かめない）
struct DemoAppleAuthorizer: AppleAuthorizing {
    /// 返す ID トークン（擬似のサーバーの Apple のアカウントの目印）
    static let demoIDToken = "demo-apple-account"

    /// 返す authorization code（トークンの取り消しに使う）
    static let demoAuthorizationCode = "demo-apple-authorization-code"

    /// 返す ID トークン
    var idToken = Self.demoIDToken

    func authorize(nonceHash: String) async throws -> String? {
        idToken
    }

    func authorizationCode() async throws -> String? {
        Self.demoAuthorizationCode
    }
}
