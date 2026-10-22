//
//  AppleAuthorization.swift
//  Dokogacha
//

import AuthenticationServices
import SwiftUI

/// Sign in with Apple の認証の画面を出し、ID トークンを受け取る窓口。設定の Model（`SettingsModel`）はこの protocol だけを見て、テストでは差し替える。
protocol AppleAuthorizing {
    /// Apple の認証の画面を出す。ユーザーがやめたら nil を返す（失敗したら `AppError` を投げる）
    /// - Parameter nonceHash: 要求に付ける nonce の SHA-256（`AppleSignInNonce.sha256`）
    /// - Returns: ID トークン（JWT の文字列）
    func authorize(nonceHash: String) async throws -> String?
}

/// AuthenticationServices の Sign in with Apple（SwiftUI の `@Environment(\.authorizationController)` で受け取ったもので要求する）。
///
/// `ASAuthorizationController` の delegate を自分で持たずに済むよう、iOS 16.4 からの `AuthorizationController` の async の API を使う
/// （delegate の分離を MainActor にそろえる手間と、`ASAuthorizationControllerPresentationContextProviding` の窓の取り出しが要らない）。
/// 名前とメールアドレスは要求しない（`requestedScopes = []`。プライバシーポリシーの収集するデータに無く、使う場所も無いため）
struct SystemAppleAuthorizer: AppleAuthorizing {
    /// 画面の環境の `authorizationController`
    let controller: AuthorizationController

    func authorize(nonceHash: String) async throws -> String? {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = nonceHash
        let result: ASAuthorizationResult
        do {
            result = try await controller.performRequest(request)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return nil
        } catch {
            throw AppError(.appleSignInFailed)
        }
        guard case let .appleID(credential) = result,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw AppError(.appleSignInFailed)
        }
        return token
    }
}
