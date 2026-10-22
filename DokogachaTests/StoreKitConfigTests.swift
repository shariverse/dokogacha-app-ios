//
//  StoreKitConfigTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ローカル確認用の StoreKit の設定（`StoreKit/Dokogacha.storekit`）と backend の `verifyPurchase` の設定が、
/// アプリの広告非表示のアイテムの定数（`DomainConstants.RemoveAds`。06 の §4 の仮決め）と食い違っていないことを確かめる。
///
/// どれもリポジトリのファイルを `#filePath` から読む（`UniversalLinksConfigTests` と同じ）。Simulator では App Store の購入を確かめられないので、
/// 設定の食い違いはここで見つける
struct StoreKitConfigTests {
    /// `.storekit` の中のアイテム（使う鍵だけ）
    private struct StoreKitProduct: Decodable {
        let productID: String
        let type: String
        let displayPrice: String
    }

    /// `.storekit` の中身（使う鍵だけ）
    private struct Configuration: Decodable {
        let products: [StoreKitProduct]
    }

    /// `StoreKit/Dokogacha.storekit` を読む
    private static func configuration() throws -> Configuration {
        let url = UniversalLinksConfigTests.repositoryRoot.appending(path: "StoreKit/Dokogacha.storekit")
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
    }

    /// 広告非表示のアイテムが 1 つだけあり、ID・種類（非消耗型）・価格（¥480）が定数と同じ
    @Test
    func storeKitConfigurationMatchesConstants() throws {
        let products = try Self.configuration().products
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.productID == DomainConstants.RemoveAds.productID)
        #expect(product.type == "NonConsumable")
        #expect(product.displayPrice == String(DomainConstants.RemoveAds.priceYen))
    }

    /// `.storekit` はアプリのリソースに入らない（`Dokogacha/` の外に置く）
    @Test
    func storeKitConfigurationIsNotBundled() {
        #expect(Bundle.main.url(forResource: "Dokogacha", withExtension: "storekit") == nil)
    }

    /// backend の定数とパラメータの既定値（アイテムの ID・Bundle ID）が、アプリと同じ
    @Test
    func backendUsesSameProductAndBundleID() throws {
        let root = UniversalLinksConfigTests.repositoryRoot
        let constants = try String(contentsOf: root.appending(path: "backend/functions/src/domain/constants.ts"), encoding: .utf8)
        #expect(constants.contains("export const REMOVE_ADS_PRODUCT_ID = \"\(DomainConstants.RemoveAds.productID)\";"))
        #expect(constants.contains("export const REMOVE_ADS_PRICE_YEN = \(DomainConstants.RemoveAds.priceYen);"))
        let functions = try String(contentsOf: root.appending(path: "backend/functions/src/purchase/functions.ts"), encoding: .utf8)
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(functions.contains("default: \"\(bundleID)\""))
    }
}
