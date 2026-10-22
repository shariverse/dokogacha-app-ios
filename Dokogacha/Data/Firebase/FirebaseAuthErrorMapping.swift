//
//  FirebaseAuthErrorMapping.swift
//  Dokogacha
//

@preconcurrency import FirebaseAuth
import Foundation

/// Firebase Auth のエラーの番号から、アプリの結果とエラーを決める（`FirebaseAuthService` の分け方を Unit テストで確かめるため。PR #100 の持ち越し）。
///
/// SDK のエラーは番号（`AuthErrorCode` の `rawValue`）と `userInfo` で届く。ここではその番号と、
/// 「サインインし直すための資格情報が付いていたか」だけを受け取り、SDK の型を外に出さない。
nonisolated enum FirebaseAuthErrorMapping {
    /// このアプリが見分ける Firebase Auth のエラーの番号
    enum Code {
        /// その Apple ID は既に今のアカウントに連携されている（17015）
        static let providerAlreadyLinked = AuthErrorCode.providerAlreadyLinked.rawValue
        /// その Apple ID は既に別のアカウントに使われている（17025）
        static let credentialAlreadyInUse = AuthErrorCode.credentialAlreadyInUse.rawValue
        /// 通信できなかった（17020）
        static let networkError = AuthErrorCode.networkError.rawValue
    }

    /// `link(with:)` が失敗したときの結果。
    ///
    /// - 既に今のアカウントに連携済み → 連携した（`.linked`）
    /// - 別のアカウントに使われている → サインインし直せる資格情報があれば `.alreadyInUse`、無ければ「Apple でサインインできませんでした」
    /// - 通信の失敗 → 「通信できませんでした」。それ以外 → 「Apple でサインインできませんでした」
    /// - Parameters:
    ///   - code: エラーの番号
    ///   - hasUpdatedCredential: `userInfo` にサインインし直すための資格情報（`AuthErrors.userInfoUpdatedCredentialKey`）が付いていたか
    static func linkResult(code: Int, hasUpdatedCredential: Bool) -> Result<AppleLinkOutcome, AppError> {
        switch code {
        case Code.providerAlreadyLinked:
            .success(.linked)
        case Code.credentialAlreadyInUse where hasUpdatedCredential:
            .success(.alreadyInUse)
        case Code.credentialAlreadyInUse:
            .failure(AppError(.appleSignInFailed))
        default:
            .failure(signInError(code: code))
        }
    }

    /// サインイン・連携のエラー（通信の失敗は「通信できませんでした」、それ以外は「Apple でサインインできませんでした」）
    static func signInError(code: Int) -> AppError {
        code == Code.networkError ? AppError(.network) : AppError(.appleSignInFailed)
    }

    /// トークンの取り消しのエラー（通信の失敗は「通信できませんでした」、それ以外は「連携を解除できませんでした」）
    static func revokeError(code: Int) -> AppError {
        code == Code.networkError ? AppError(.network) : AppError(.appleRevokeFailed)
    }
}
