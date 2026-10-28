//
//  SettingsRulesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の判定（Sign in with Apple の nonce と連携済みの判定・購入の行の状態・トーストの文言・バージョンの表示・entitlements）を確かめる
struct SettingsRulesTests {
    /// 決まった数を順に返す乱数（nonce の文字の選び方を決めるため）
    struct SequenceGenerator: RandomNumberGenerator {
        var values: [UInt64]
        var index = 0

        mutating func next() -> UInt64 {
            defer { index = (index + 1) % values.count }
            return values[index]
        }
    }

    // MARK: nonce

    /// nonce は 32 文字で、決めた文字だけを使う
    @Test
    func nonceHasFixedLengthAndCharacters() {
        let nonce = AppleSignInNonce.make()
        #expect(nonce.count == AppleSignInNonce.length)
        #expect(nonce.allSatisfy { AppleSignInNonce.characters.contains($0) })
        #expect(AppleSignInNonce.characters.count == 65)
        #expect(Set(AppleSignInNonce.characters).count == AppleSignInNonce.characters.count)
    }

    /// 乱数を注入すれば同じ nonce になり、別の乱数なら別の nonce になる（毎回の要求で使い回さない）
    @Test
    func nonceDependsOnRandomness() {
        // `Int.random(in:using:)` は乱数の上位のビットで選ぶので、大きな値を流す
        let values: [UInt64] = [UInt64.max / 3, UInt64.max / 5 * 4, UInt64.max / 7]
        var first = SequenceGenerator(values: values)
        var again = SequenceGenerator(values: values)
        var other = SequenceGenerator(values: values.reversed())
        let nonce = AppleSignInNonce.make(length: 8, using: &first)
        #expect(nonce == AppleSignInNonce.make(length: 8, using: &again))
        #expect(nonce != AppleSignInNonce.make(length: 8, using: &other))
        let systemNonce = AppleSignInNonce.make()
        let anotherSystemNonce = AppleSignInNonce.make()
        #expect(systemNonce != anotherSystemNonce)
    }

    /// Apple に渡すハッシュは SHA-256 の 16 進の小文字（FIPS 180-2 の "abc" の例）
    @Test
    func nonceHashIsLowercaseHexSHA256() {
        #expect(AppleSignInNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(AppleSignInNonce.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// 連携済みかは、アカウントのプロバイダに Apple（`apple.com`）があるか
    @Test(arguments: [
        ([], false),
        (["password"], false),
        (["apple.com"], true),
        (["google.com", "apple.com"], true)
    ] as [([String], Bool)])
    func appleLinkIsDecidedByProvider(providerIDs: [String], linked: Bool) {
        #expect(AppleAccountLink.isLinked(providerIDs: providerIDs) == linked)
    }

    // MARK: 購入の行

    /// 購入済みなら「広告非表示：購入済み」。まだなら App Store の価格、読めなければ仮決めの ¥480（03 の S-15）
    @Test
    func removeAdsRowShowsPriceOrPurchased() {
        #expect(RemoveAdsRowState.make(isAdFree: true, displayPrice: "¥480") == .purchased)
        #expect(RemoveAdsRowState.make(isAdFree: true, displayPrice: nil) == .purchased)
        #expect(RemoveAdsRowState.make(isAdFree: false, displayPrice: "¥500") == .available(price: "¥500"))
        #expect(RemoveAdsRowState.make(isAdFree: false, displayPrice: nil) == .available(price: "¥480"))
        #expect(RemoveAdsRowState.make(isAdFree: false, displayPrice: " ") == .available(price: "¥480"))
        #expect(RemoveAdsRowState.fallbackPrice == "¥\(DomainConstants.RemoveAds.priceYen)")
    }

    /// 購入の結果の文言（やめたときは出さない）と、復元の結果の文言
    @Test
    func purchaseFeedbackMessages() {
        let purchase = SignedPurchase(productID: DomainConstants.RemoveAds.productID, transactionID: "1", signedTransaction: "jws")
        #expect(PurchaseFeedback.message(for: .purchased(purchase)) == "広告を非表示にしました")
        #expect(PurchaseFeedback.message(for: .pending) == "購入の承認待ちです。承認されると広告が消えます")
        #expect(PurchaseFeedback.message(for: .cancelled) == nil)
        #expect(PurchaseFeedback.restoreMessage(restored: true) == "購入を復元しました")
        #expect(PurchaseFeedback.restoreMessage(restored: false) == "復元できる購入がありません")
    }

    // MARK: バージョン

    /// バージョンは「1.0.0（1）」。ビルド番号が無ければバージョンだけ、バージョンが無ければ空
    @Test
    func appVersionTextFormatsVersionAndBuild() {
        #expect(AppVersionText.make(shortVersion: "1.0.0", build: "1") == "1.0.0（1）")
        #expect(AppVersionText.make(shortVersion: "1.2", build: nil) == "1.2")
        #expect(AppVersionText.make(shortVersion: "1.2", build: "") == "1.2")
        #expect(AppVersionText.make(shortVersion: nil, build: "3").isEmpty)
    }

    /// アプリの Info.plist の値で作る（xcconfig の `MARKETING_VERSION`・`CURRENT_PROJECT_VERSION`）
    @Test
    func appVersionTextReadsBundle() throws {
        let settings = try UniversalLinksConfigTests.projectSettings()
        let version = try #require(settings["MARKETING_VERSION"])
        let build = try #require(settings["CURRENT_PROJECT_VERSION"])
        #expect(AppVersionText.make(bundle: .main) == "\(version)（\(build)）")
    }

    // MARK: entitlements

    /// entitlements に Sign in with Apple（`Default`）がある
    @Test
    func entitlementsDeclareSignInWithApple() throws {
        let url = UniversalLinksConfigTests.repositoryRoot.appending(path: "Configs/Dokogacha.entitlements")
        let plist = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["com.apple.developer.applesignin"] as? [String] == ["Default"])
    }
}
