//
//  PurchaseService.swift
//  Dokogacha
//

import Foundation

/// 広告非表示のアイテム（StoreKit の `Product` から写した値。S-15 の「広告を非表示にする（¥480）」に出す）
nonisolated struct PurchaseProduct: Equatable, Sendable {
    /// アイテムの ID
    let id: String
    /// App Store の価格の表示（「¥480」。地域の通貨で StoreKit が作る）
    let displayPrice: String
}

/// 購入の結果
nonisolated enum PurchaseOutcome: Equatable, Sendable {
    /// 買った（StoreKit で確かめた購入。サーバーにも送る）
    case purchased(SignedPurchase)
    /// 購入の確認でやめた
    case cancelled
    /// 承認待ち（ファミリー共有の「承認と購入のリクエスト」など）。承認されたら `transactionUpdates` に届く
    case pending
}

/// 広告非表示の買い切り（F-51）の StoreKit 2 の窓口。`PurchaseCoordinator` はこの protocol だけを見て、テストでは差し替える。
///
/// StoreKit の購入の確認（端末の署名の検証）はこの中で行い、確かめたものだけを `SignedPurchase` で返す。
/// サーバーでの確認（`verifyPurchase`）は `PurchaseCoordinator` が行う。失敗したときは `AppError` を投げる
protocol PurchaseService {
    /// 広告非表示のアイテム（`Product.products(for:)`）。App Store に無ければ nil
    func product() async throws -> PurchaseProduct?
    /// 広告非表示のアイテムを買う（`Product.purchase()`。買えたら `Transaction.finish()` まで行う）
    func purchase() async throws -> PurchaseOutcome
    /// いま持っている広告非表示のアイテム（`Transaction.currentEntitlements`。返金などで取り消されたものは除く）。無ければ nil
    func currentEntitlement() async -> SignedPurchase?
    /// 購入を復元する（`AppStore.sync()` の後の `currentEntitlement`）。復元するものが無ければ nil
    func restore() async throws -> SignedPurchase?
    /// アプリの外で起きた購入の変化（`Transaction.updates`。承認待ちの承認・別の端末での購入・返金）。
    ///
    /// 変化があるたびに、その後の `currentEntitlement` を流す。購読をやめる（`Task` を cancel する）と StoreKit の購読も止まる
    func transactionUpdates() -> AsyncStream<SignedPurchase?>
}

/// 購入を使わないときの窓口（Unit テストのホスト・`-uiTesting`・撮影モード・プレビュー）。何も持たず、買えない
struct DisabledPurchaseService: PurchaseService {
    func product() async throws -> PurchaseProduct? {
        nil
    }

    func purchase() async throws -> PurchaseOutcome {
        throw AppError(.notImplemented)
    }

    func currentEntitlement() async -> SignedPurchase? {
        nil
    }

    func restore() async throws -> SignedPurchase? {
        nil
    }

    func transactionUpdates() -> AsyncStream<SignedPurchase?> {
        AsyncStream { $0.finish() }
    }
}
