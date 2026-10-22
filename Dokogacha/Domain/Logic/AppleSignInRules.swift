//
//  AppleSignInRules.swift
//  Dokogacha
//
//  Sign in with Apple の連携（02 の §1 F-01）の判定。Firebase Auth と AuthenticationServices から切り出した値だけで決める純粋な関数。
//

import CryptoKit
import Foundation

/// Sign in with Apple の要求に付ける nonce（使い捨ての乱数の文字列）。
///
/// Apple には SHA-256 のハッシュを渡し、Firebase にはハッシュにする前の値を渡す。Firebase は ID トークンに入ったハッシュと
/// 突き合わせて、盗まれた ID トークンを使い回されていないかを確かめる（Firebase の Sign in with Apple の手順）
nonisolated enum AppleSignInNonce {
    /// nonce の長さ（Firebase の手順の例と同じ 32 文字）
    static let length = 32
    /// nonce に使う文字（英数字と `-._`。どれも URL・JWT でそのまま使える）
    static let characters: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    /// nonce を作る（乱数はテストで決められるよう注入する）
    /// - Parameters:
    ///   - length: 長さ
    ///   - generator: 乱数（アプリでは暗号論的に安全な `SystemRandomNumberGenerator`）
    static func make(length: Int = length, using generator: inout some RandomNumberGenerator) -> String {
        String((0..<length).map { _ in characters[Int.random(in: characters.indices, using: &generator)] })
    }

    /// 端末の安全な乱数で nonce を作る
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    /// Apple に渡す nonce のハッシュ（SHA-256 の 16 進の小文字）
    static func sha256(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Sign in with Apple に連携済みかの判定（S-15 の「連携済み」）。
nonisolated enum AppleAccountLink {
    /// Firebase Auth の Apple のプロバイダの ID
    static let providerID = "apple.com"

    /// アカウントに連携されたプロバイダ（Firebase の `User.providerData` の `providerID`）に Apple があるか
    static func isLinked(providerIDs: [String]) -> Bool {
        providerIDs.contains(providerID)
    }
}
