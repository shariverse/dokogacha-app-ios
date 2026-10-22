//
//  PurchaseCoordinator.swift
//  Dokogacha
//

import Foundation
import Observation
import OSLog

/// 広告非表示の買い切り（F-51）のまとめ役。`AppDelegate` が 1 つ持ち、`DokoGachaApp` が `@Environment` で画面に渡す。
///
/// - 起動したら（`start`）端末の購入（`Transaction.currentEntitlements`）を読み、`Transaction.updates` を購読する（05 の §8）。
///   購読はこのまとめ役が無くなったら止める
/// - 端末に購入があり、サーバーがまだ記録していなければ `verifyPurchase` を呼ぶ（05 の §8「初回のみ」。`PurchaseVerificationPolicy`）。
///   サーバーの記録（`users.adFree`）とサーバーの窓口は、起動の流れ（`RootView`）がプロフィールを読むたびに `connect` で渡す
/// - 広告を出すかの判定には、サーバーの記録と端末の購入のどちらかがあれば広告非表示とする（`isAdFree(serverAdFree:)`）
/// - 購入（`purchase`）と復元（`restore`）は、設定の画面（S-15。タスク 38）から呼ぶ
@Observable
final class PurchaseCoordinator {
    /// 購入の失敗を残すログ
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Purchase")

    /// 端末で持っている広告非表示の購入（StoreKit で確かめたもの。無ければ nil）
    private(set) var entitlement: SignedPurchase?

    @ObservationIgnored private let service: any PurchaseService
    /// サーバーの窓口（`connect` で受け取る。プロフィールが読めるまでは nil）
    @ObservationIgnored private var functions: (any FunctionsClient)?
    /// サーバーの `users.adFree`（プロフィールが読めるまでは nil）
    @ObservationIgnored private var serverAdFree: Bool?
    /// サインインしているユーザー（替わったら、送ったトランザクションを忘れて新しいユーザーにも送る）
    @ObservationIgnored private var userID: String?
    /// この起動でいまのユーザーにもう送ったトランザクション（同じものを何度も送らない）
    @ObservationIgnored private var sentTransactionIDs: Set<String> = []
    /// 端末の購入を読み、`Transaction.updates` を購読している処理（このまとめ役が無くなったら止める。テストで終わりを待てるよう読み取りだけ公開する）
    @ObservationIgnored private(set) var updatesTask: Task<Void, Never>?
    /// 端末の購入をサーバーに送っている処理（テストで終わりを待てるよう読み取りだけ公開する）
    @ObservationIgnored private(set) var verifyTask: Task<Void, Never>?

    /// - Parameter service: StoreKit の窓口（テストでは差し替える）
    init(service: any PurchaseService) {
        self.service = service
    }

    deinit {
        updatesTask?.cancel()
        verifyTask?.cancel()
    }

    /// 購入を使わないまとめ役（Unit テストのホスト・`-uiTesting`・撮影モード・プレビュー）
    static var disabled: PurchaseCoordinator {
        PurchaseCoordinator(service: DisabledPurchaseService())
    }

    /// 起動のしかたに合わせたまとめ役。Unit テストのホスト・`-uiTesting`・撮影モードでは StoreKit を使わない
    /// （購入の確認のシートがテストの画面を塞がないように。擬似のサーバーの購入者はデモのデータで用意する）
    static func make(launch: LaunchContext) -> PurchaseCoordinator {
        if launch.isUnitTestHost || launch.isUITesting || launch.isScreenshotDemo {
            return .disabled
        }
        return PurchaseCoordinator(service: StoreKitPurchaseService())
    }

    /// 自分を広告非表示として扱うか（サーバーの記録か、端末の購入のどちらかがあれば。`AdFreeStatus`）
    /// - Parameter serverAdFree: サーバーの `users.adFree`
    func isAdFree(serverAdFree: Bool) -> Bool {
        AdFreeStatus.isAdFree(serverAdFree: serverAdFree, hasEntitlement: entitlement != nil)
    }

    /// 起動したとき。端末の購入を読み、`Transaction.updates` を購読する（2 回目以降は何もしない）
    func start() {
        guard updatesTask == nil else {
            return
        }
        let service = service
        updatesTask = Task { [weak self] in
            let current = await service.currentEntitlement()
            self?.apply(current)
            for await entitlement in service.transactionUpdates() {
                self?.apply(entitlement)
            }
        }
    }

    /// サインインの状態・プロフィールが変わったとき。サーバーの記録を受け取り、端末の購入をまだ記録していなければ送る。
    ///
    /// ユーザーが替わったら（匿名のユーザーが作り直された・別の Apple ID でサインインした）、新しいユーザーにも送る
    /// （サーバーは呼んだ人を広告非表示にするので、端末の購入は今のユーザーに記録する）
    /// - Parameters:
    ///   - functions: サーバーの窓口
    ///   - userID: サインインしているユーザー（していなければ nil）
    ///   - serverAdFree: サーバーの `users.adFree`（プロフィールが読めていなければ nil）
    func connect(functions: any FunctionsClient, userID: String?, serverAdFree: Bool?) {
        if userID != self.userID {
            sentTransactionIDs = []
        }
        self.functions = functions
        self.userID = userID
        self.serverAdFree = serverAdFree
        verifyIfNeeded()
    }

    /// 広告非表示のアイテムを買う（S-15 の「広告を非表示にする（¥480）」）。買えたらサーバーにも送る（送れなければ投げる）
    func purchase() async throws -> PurchaseOutcome {
        let outcome = try await service.purchase()
        if case let .purchased(purchase) = outcome {
            entitlement = purchase
            try await send(purchase)
        }
        return outcome
    }

    /// 購入を復元する（S-15 の「購入を復元」・02 の F-51 の AC「購入を復元すると広告が消える」）。復元できたら true（サーバーにも送る）
    func restore() async throws -> Bool {
        guard let restored = try await service.restore() else {
            return false
        }
        entitlement = restored
        try await send(restored)
        return true
    }

    /// 端末の購入が変わったとき
    private func apply(_ entitlement: SignedPurchase?) {
        self.entitlement = entitlement
        verifyIfNeeded()
    }

    /// 端末に購入があり、サーバーがまだ記録していなければ、裏で送る（失敗はログに残し、次の起動で送り直す）
    private func verifyIfNeeded() {
        guard verifyTask == nil,
              PurchaseVerificationPolicy.shouldVerify(
                  entitlement: entitlement,
                  serverAdFree: serverAdFree,
                  sentTransactionIDs: sentTransactionIDs
              ),
              let entitlement else {
            return
        }
        verifyTask = Task { [weak self] in
            do {
                try await self?.send(entitlement)
            } catch {
                Self.logger.error("購入をサーバーに記録できませんでした: \(AppError.wrapping(error).reason.rawValue, privacy: .public)")
            }
            self?.verifyTask = nil
        }
    }

    /// 購入をサーバーに送る（`verifyPurchase`。サーバーの窓口がまだ無ければ送らない。次に `connect` されたときに送る）
    private func send(_ purchase: SignedPurchase) async throws {
        guard let functions else {
            return
        }
        sentTransactionIDs.insert(purchase.transactionID)
        let response = try await functions.verifyPurchase(VerifyPurchaseRequest(signedTransaction: purchase.signedTransaction))
        if response.adFree {
            serverAdFree = true
        }
    }
}
