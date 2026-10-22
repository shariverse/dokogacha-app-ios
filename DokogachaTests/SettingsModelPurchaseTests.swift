//
//  SettingsModelPurchaseTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の広告非表示の購入と復元（02 の §7.2 F-51「設定画面に『広告を非表示にする（¥480）』『購入を復元』」）を、
/// StoreKit を差し替えたまとめ役で確かめる（行の表示・購入済み・承認待ち・失敗のトースト・二重に押せないこと）
struct SettingsModelPurchaseTests {
    typealias ControlledAuth = OnboardingModelTests.ControlledAuth

    /// StoreKit を差し替えたもの（価格・購入・復元の結果を決められる。`suspendsPurchase` なら `finishPurchase` まで止まる）
    final class StubPurchaseService: PurchaseService {
        var product: PurchaseProduct? = PurchaseProduct(id: DomainConstants.RemoveAds.productID, displayPrice: "¥500")
        var productError: AppError?
        var purchaseOutcome: PurchaseOutcome = .cancelled
        var purchaseError: AppError?
        var restored: SignedPurchase?
        var restoreError: AppError?
        var suspendsPurchase = false
        /// 購入が呼ばれた回数
        private(set) var purchaseCount = 0
        private var pending: CheckedContinuation<Void, Never>?

        /// 購入の途中で止まっているか
        var isWaiting: Bool {
            pending != nil
        }

        /// 止めていた購入を進める
        func finishPurchase() {
            pending?.resume()
            pending = nil
        }

        func product() async throws -> PurchaseProduct? {
            if let productError {
                throw productError
            }
            return product
        }

        func purchase() async throws -> PurchaseOutcome {
            purchaseCount += 1
            if suspendsPurchase {
                await withCheckedContinuation { pending = $0 }
            }
            if let purchaseError {
                throw purchaseError
            }
            return purchaseOutcome
        }

        func currentEntitlement() async -> SignedPurchase? {
            nil
        }

        func restore() async throws -> SignedPurchase? {
            if let restoreError {
                throw restoreError
            }
            return restored
        }

        func transactionUpdates() -> AsyncStream<SignedPurchase?> {
            AsyncStream { $0.finish() }
        }
    }

    /// 端末で確かめた購入
    static let signedPurchase = SignedPurchase(
        productID: DomainConstants.RemoveAds.productID,
        transactionID: "2000000000000001",
        signedTransaction: "signed-jws"
    )

    static func makeModel(
        service: StubPurchaseService,
        auth: ControlledAuth = ControlledAuth(scenario: .oneRoom),
        toasts: DGToastCenter = OnboardingModelTests.makeToasts()
    ) -> SettingsModel {
        SettingsModel(
            userID: DemoScenario.myUserID,
            auth: auth,
            purchases: PurchaseCoordinator(service: service),
            toasts: toasts,
            resubscribeDelay: SettingsModelTests.stopResubscribe
        )
    }

    // MARK: 行の表示

    /// 価格は App Store の表示を使い、読めないときは仮決めの ¥480 のまま（トーストは出さない）
    @Test
    func showsStorePriceOrFallback() async {
        let service = StubPurchaseService()
        let model = Self.makeModel(service: service)
        #expect(model.removeAdsRow == .available(price: "¥480"))
        await model.loadProduct()
        #expect(model.removeAdsRow == .available(price: "¥500"))

        let failing = StubPurchaseService()
        failing.productError = AppError(.network)
        let toasts = OnboardingModelTests.makeToasts()
        let offline = Self.makeModel(service: failing, toasts: toasts)
        await offline.loadProduct()
        #expect(offline.removeAdsRow == .available(price: "¥480"))
        #expect(toasts.current == nil)
    }

    /// サーバーが購入を記録していれば（`users.adFree`）「広告非表示：購入済み」にする（ほかの端末で買ったときも）
    @Test
    func serverRecordShowsPurchased() async throws {
        let auth = ControlledAuth(scenario: .oneRoom)
        let model = Self.makeModel(service: StubPurchaseService(), auth: auth)
        let observing = Task { await model.observe() }
        try #require(await AsyncTestSupport.eventually { model.hasLoadedProfile })
        #expect(model.removeAdsRow == .available(price: "¥480"))

        auth.server.users[DemoScenario.myUserID]?.adFree = true
        #expect(await AsyncTestSupport.eventually { model.removeAdsRow == .purchased })
        observing.cancel()
    }

    // MARK: 購入

    /// 買えたら購入済みにして「広告を非表示にしました」（サーバーの記録が届く前でも、端末の購入で購入済みにする）
    @Test
    func purchaseMarksPurchasedAndShowsToast() async {
        let service = StubPurchaseService()
        service.purchaseOutcome = .purchased(Self.signedPurchase)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: service, toasts: toasts)

        await model.purchase()
        #expect(model.removeAdsRow == .purchased)
        #expect(toasts.current?.text == "広告を非表示にしました")
        #expect(model.activeAction == nil)

        // 購入済みになったら、もう買わない
        await model.purchase()
        #expect(service.purchaseCount == 1)
    }

    /// 承認待ちなら、購入済みにせずに「購入の承認待ちです。承認されると広告が消えます」
    @Test
    func pendingPurchaseShowsToast() async {
        let service = StubPurchaseService()
        service.purchaseOutcome = .pending
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: service, toasts: toasts)

        await model.purchase()
        #expect(model.removeAdsRow == .available(price: "¥480"))
        #expect(toasts.current?.text == "購入の承認待ちです。承認されると広告が消えます")
    }

    /// 購入の確認でやめたら、何も出さない
    @Test
    func cancelledPurchaseShowsNothing() async {
        let service = StubPurchaseService()
        service.purchaseOutcome = .cancelled
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: service, toasts: toasts)

        await model.purchase()
        #expect(toasts.current == nil)
        #expect(model.removeAdsRow == .available(price: "¥480"))
    }

    /// 失敗したらエラーの文言のトーストを出し、もう一度押せる（StoreKit の cancel ではトーストを出さない）
    @Test
    func failedPurchaseShowsErrorToast() async {
        let service = StubPurchaseService()
        service.purchaseError = AppError(.purchaseInvalid)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: service, toasts: toasts)

        await model.purchase()
        #expect(toasts.current?.text == "購入を確認できませんでした")
        #expect(model.canStartAction)

        let cancelled = StubPurchaseService()
        cancelled.purchaseError = AppError(.cancelled)
        let quiet = OnboardingModelTests.makeToasts()
        await Self.makeModel(service: cancelled, toasts: quiet).purchase()
        #expect(quiet.current == nil)
    }

    /// 購入の途中は、購入・復元・連携のどれも押せず、続けて押しても 1 回しか買わない
    @Test
    func purchaseInProgressBlocksOtherActions() async throws {
        let service = StubPurchaseService()
        service.suspendsPurchase = true
        service.purchaseOutcome = .purchased(Self.signedPurchase)
        let model = Self.makeModel(service: service)

        model.purchaseTapped()
        model.purchaseTapped()
        try #require(await AsyncTestSupport.eventually { service.isWaiting })
        #expect(model.activeAction == .purchase)
        #expect(!model.canStartAction)
        model.restoreTapped()

        service.finishPurchase()
        #expect(await AsyncTestSupport.eventually { model.activeAction == nil })
        #expect(service.purchaseCount == 1)
        #expect(model.removeAdsRow == .purchased)
    }

    // MARK: 復元

    /// 復元できたら購入済みにして「購入を復元しました」（02 の F-51 の AC「購入を復元すると広告が消える」）
    @Test
    func restoreMarksPurchased() async {
        let service = StubPurchaseService()
        service.restored = Self.signedPurchase
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: service, toasts: toasts)

        await model.restore()
        #expect(model.removeAdsRow == .purchased)
        #expect(toasts.current?.text == "購入を復元しました")
    }

    /// 復元するものが無ければ「復元できる購入がありません」、失敗したらエラーの文言
    @Test
    func restoreWithoutPurchaseOrFailure() async {
        let none = StubPurchaseService()
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(service: none, toasts: toasts)
        await model.restore()
        #expect(model.removeAdsRow == .available(price: "¥480"))
        #expect(toasts.current?.text == "復元できる購入がありません")

        let failing = StubPurchaseService()
        failing.restoreError = AppError(.network)
        let failureToasts = OnboardingModelTests.makeToasts()
        await Self.makeModel(service: failing, toasts: failureToasts).restore()
        #expect(failureToasts.current?.text == "通信できませんでした")
    }
}
