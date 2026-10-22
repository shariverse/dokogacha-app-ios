//
//  StoreKitPurchaseService.swift
//  Dokogacha
//

import Foundation
import OSLog
import StoreKit

/// StoreKit 2 での広告非表示の買い切り（F-51。非消耗型アイテム `remove_ads`）。
///
/// - 端末の署名の検証（`VerificationResult.verified`）を通ったものだけを購入として扱い、サーバーには `jwsRepresentation` を送る
/// - 購入・承認待ちの承認・復元のトランザクションは `finish()` する（しないと `Transaction.updates` に届き続ける）
/// - ローカルでは `StoreKit/Dokogacha.storekit`（Xcode のスキームの StoreKit Configuration に設定する）で、App Store Connect の登録なしに買える
struct StoreKitPurchaseService: PurchaseService {
    /// 購入の失敗を残すログ
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Purchase")

    /// 広告非表示のアイテムの ID
    let productID: String

    /// - Parameter productID: 広告非表示のアイテムの ID（既定は 06 の §4 の仮決めの `remove_ads`）
    init(productID: String = DomainConstants.RemoveAds.productID) {
        self.productID = productID
    }

    func product() async throws -> PurchaseProduct? {
        try await storeProduct().map { PurchaseProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }

    func purchase() async throws -> PurchaseOutcome {
        guard let product = try await storeProduct() else {
            throw AppError(.purchaseInvalid)
        }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            Self.logger.error("購入に失敗しました: \(String(describing: error), privacy: .public)")
            throw Self.appError(from: error)
        }
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw AppError(.purchaseInvalid)
            }
            await transaction.finish()
            return .purchased(Self.signedPurchase(transaction, verification: verification))
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    func currentEntitlement() async -> SignedPurchase? {
        await Self.entitlement(productID: productID)
    }

    func restore() async throws -> SignedPurchase? {
        do {
            try await AppStore.sync()
        } catch {
            Self.logger.error("購入の復元に失敗しました: \(String(describing: error), privacy: .public)")
            throw Self.appError(from: error)
        }
        return await currentEntitlement()
    }

    func transactionUpdates() -> AsyncStream<SignedPurchase?> {
        let productID = productID
        let (stream, continuation) = AsyncStream.makeStream(of: SignedPurchase?.self)
        let task = Task {
            for await verification in Transaction.updates {
                if case let .verified(transaction) = verification {
                    await transaction.finish()
                }
                guard verification.unsafePayloadValue.productID == productID else {
                    continue
                }
                continuation.yield(await Self.entitlement(productID: productID))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    /// App Store の広告非表示のアイテム（無ければ nil）
    private func storeProduct() async throws -> Product? {
        do {
            return try await Product.products(for: [productID]).first
        } catch {
            Self.logger.error("アイテムを読み込めませんでした: \(String(describing: error), privacy: .public)")
            throw Self.appError(from: error)
        }
    }

    /// いま持っている広告非表示のアイテム（端末の署名を確かめたもの・取り消されていないものだけ）
    private static func entitlement(productID: String) async -> SignedPurchase? {
        for await verification in Transaction.currentEntitlements {
            guard case let .verified(transaction) = verification,
                  transaction.productID == productID,
                  transaction.revocationDate == nil else {
                continue
            }
            return signedPurchase(transaction, verification: verification)
        }
        return nil
    }

    /// 確かめたトランザクションを、サーバーに送る値にする
    private static func signedPurchase(_ transaction: Transaction, verification: VerificationResult<Transaction>) -> SignedPurchase {
        SignedPurchase(
            productID: transaction.productID,
            transactionID: String(transaction.id),
            signedTransaction: verification.jwsRepresentation
        )
    }

    /// StoreKit のエラーをアプリのエラーにする（購入の確認でやめたものは cancel として扱い、トーストを出さない）
    private static func appError(from error: any Error) -> AppError {
        if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError {
            return AppError(.cancelled)
        }
        return AppError(.network)
    }
}
