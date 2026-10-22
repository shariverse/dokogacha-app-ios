//
//  FirebaseAuthErrorMappingTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// Sign in with Apple の連携（`link(with:)`）とトークンの取り消しのエラーの分け方を確かめる（PR #100 の持ち越し）
struct FirebaseAuthErrorMappingTests {
    /// SDK の番号が、Firebase のドキュメントの値のまま（SDK を上げて番号が変わったら気づく）
    @Test
    func codesMatchFirebaseDocumentation() {
        #expect(FirebaseAuthErrorMapping.Code.providerAlreadyLinked == 17_015)
        #expect(FirebaseAuthErrorMapping.Code.credentialAlreadyInUse == 17_025)
        #expect(FirebaseAuthErrorMapping.Code.networkError == 17_020)
    }

    /// 既に今のアカウントに連携済みなら、連携したことにする
    @Test
    func providerAlreadyLinkedIsLinked() {
        let code = FirebaseAuthErrorMapping.Code.providerAlreadyLinked
        #expect(FirebaseAuthErrorMapping.linkResult(code: code, hasUpdatedCredential: false) == .success(.linked))
    }

    /// 別のアカウントに使われていて、サインインし直す資格情報があれば `.alreadyInUse`。無ければ失敗
    @Test
    func credentialAlreadyInUseNeedsUpdatedCredential() {
        let code = FirebaseAuthErrorMapping.Code.credentialAlreadyInUse
        #expect(FirebaseAuthErrorMapping.linkResult(code: code, hasUpdatedCredential: true) == .success(.alreadyInUse))
        #expect(FirebaseAuthErrorMapping.linkResult(code: code, hasUpdatedCredential: false) == .failure(AppError(.appleSignInFailed)))
    }

    /// 通信の失敗は「通信できませんでした」、知らない番号は「Apple でサインインできませんでした」
    @Test
    func otherErrorsMapToMessages() {
        let network = FirebaseAuthErrorMapping.linkResult(code: FirebaseAuthErrorMapping.Code.networkError, hasUpdatedCredential: true)
        #expect(network == .failure(AppError(.network)))
        #expect(FirebaseAuthErrorMapping.linkResult(code: 17_999, hasUpdatedCredential: true) == .failure(AppError(.appleSignInFailed)))
        #expect(FirebaseAuthErrorMapping.signInError(code: 1).message == "Apple でサインインできませんでした")
    }

    /// トークンの取り消しは、通信の失敗と、それ以外（連携を解除できませんでした）に分ける
    @Test
    func revokeErrors() {
        #expect(FirebaseAuthErrorMapping.revokeError(code: FirebaseAuthErrorMapping.Code.networkError) == AppError(.network))
        #expect(FirebaseAuthErrorMapping.revokeError(code: 17_011) == AppError(.appleRevokeFailed))
    }
}
