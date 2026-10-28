//
//  PurchaseRules.swift
//  Dokogacha
//
//  広告非表示の買い切り（02 の §7.2 F-51・05 の §8）の判定。StoreKit とサーバーから切り出した値だけで決める純粋な関数。
//  ルームの購入者の決め方は backend の `functions/src/purchase/logic.ts`（`sponsorAfterPurchase`・`joinedBefore`）と同じ。
//

import Foundation

/// StoreKit 2 で確かめた、広告非表示のアイテムの購入（`Transaction` から写した値）。
///
/// StoreKit の型をデータ層の外に出さないために持つ。サーバーには `signedTransaction` を送り、App Store の署名で確かめ直す
nonisolated struct SignedPurchase: Equatable, Sendable {
    /// アイテムの ID（`DomainConstants.RemoveAds.productID`）
    let productID: String
    /// トランザクションの ID（同じ購入を 2 回送らないための目印）
    let transactionID: String
    /// 署名付きトランザクション（`VerificationResult.jwsRepresentation`。`verifyPurchase` に送る）
    let signedTransaction: String
}

/// 自分が広告非表示を買ったかの判定（05 の §8 の `me.adFree`）。
nonisolated enum AdFreeStatus {
    /// 自分を広告非表示として扱うか。
    ///
    /// サーバーに記録した購入（`users.adFree`）か、端末の StoreKit の購入（`Transaction.currentEntitlements`）のどちらかがあれば広告を出さない。
    /// 買った直後・オフラインでサーバーの記録がまだ届かないあいだも、買った人に広告を見せないため（02 の §7.2「購入すると、購入者本人は全画面で広告が消える」）。
    /// ほかのメンバーの広告を消す（`rooms.adFreeSponsor`）のは、サーバーが確かめた購入だけ
    /// - Parameters:
    ///   - serverAdFree: サーバーの `users.adFree`
    ///   - hasEntitlement: 端末の StoreKit で広告非表示のアイテムを持っているか
    static func isAdFree(serverAdFree: Bool, hasEntitlement: Bool) -> Bool {
        serverAdFree || hasEntitlement
    }
}

/// 端末の購入をサーバーに送る（`verifyPurchase`）かの判定（05 の §8「`remove_ads` があれば `verifyPurchase` を呼ぶ（初回のみ）」）。
nonisolated enum PurchaseVerificationPolicy {
    /// いまの購入をサーバーに送るか。
    ///
    /// 端末に購入があり、プロフィールが読めていて（表示名の登録の後。`users/{uid}` が無いと `profile-required` になる）、
    /// サーバーがまだ広告非表示を記録しておらず、この起動でまだ送っていないトランザクションのときだけ送る。
    /// 失敗したら、次の起動・別のトランザクション（復元・買い直し）で送り直す（1 回の起動で同じものを何度も送らない）
    /// - Parameters:
    ///   - entitlement: 端末の購入（無ければ nil）
    ///   - serverAdFree: サーバーの `users.adFree`（プロフィールがまだ読めていなければ nil）
    ///   - sentTransactionIDs: この起動でもう送ったトランザクションの ID
    static func shouldVerify(entitlement: SignedPurchase?, serverAdFree: Bool?, sentTransactionIDs: Set<String>) -> Bool {
        guard let entitlement, let serverAdFree else {
            return false
        }
        return !serverAdFree && !sentTransactionIDs.contains(entitlement.transactionID)
    }
}

/// ルーム（S-07）の最下部に出す「◯◯さんのおかげで、このルームは広告なし」（03 の S-07・02 の §7.2）の判定。
nonisolated enum AdFreeNoticePolicy {
    /// メッセージに出す購入者の名前。出さないときは nil。
    ///
    /// ルームの画面だけで、ルームに購入者（`rooms.adFreeSponsor`）がいれば出す（03 の S-07「バナー広告、または『◯◯さんのおかげで…』」）。
    /// 購入者本人が開いたときも出す（02 の §7.2 は購入者がメンバーにいるルームに表示するとだけあり、本人を除いていない）。
    /// 名前が空のとき（届いたデータが壊れている）は出さない
    /// - Parameters:
    ///   - screen: 出そうとしている画面
    ///   - room: 開いているルーム（まだ届いていなければ nil）
    static func sponsorName(screen: AdScreen, room: Room?) -> String? {
        guard screen == .room, let sponsor = room?.adFreeSponsor else {
            return nil
        }
        let name = sponsor.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : sponsor.displayName
    }
}

/// 購入した後の、ルームの購入者（`rooms.adFreeSponsor`）の決め方（05 の §3「購入者がいれば最初に参加した人」）。
///
/// backend の `sponsorAfterPurchase` と同じ。擬似のサーバー（`InMemoryServer+Purchase.swift`）が使う
nonisolated enum AdFreeSponsorRule {
    /// 参加の順を比べるための、メンバーの uid と参加日時
    struct JoinOrder: Equatable, Sendable {
        /// uid
        let uid: String
        /// 参加日時
        let joinedAt: Date
    }

    /// `a` が `b` より先に参加したか。同じ日時なら uid の小さい方を先にする（backend の `orderBy("joinedAt")` とドキュメントの ID の順）
    static func joinedBefore(_ lhs: JoinOrder, _ rhs: JoinOrder) -> Bool {
        if lhs.joinedAt != rhs.joinedAt {
            return lhs.joinedAt < rhs.joinedAt
        }
        return lhs.uid < rhs.uid
    }

    /// 購入した後の購入者。変えないときは nil。
    ///
    /// 購入者がいなければ購入した人に、購入した人のほうが先に参加していれば購入した人に替える。それ以外は変えない
    /// - Parameters:
    ///   - current: いまの購入者
    ///   - buyer: 購入した人（参加の順）
    ///   - buyerName: 購入した人のルームでの表示名
    ///   - currentJoin: いまの購入者の参加の順（いまの購入者がいない・メンバーにいないときは nil）
    static func afterPurchase(
        current: AdFreeSponsor?,
        buyer: JoinOrder,
        buyerName: String,
        currentJoin: JoinOrder?
    ) -> AdFreeSponsor? {
        let next = AdFreeSponsor(uid: buyer.uid, displayName: buyerName)
        guard let current, let currentJoin else {
            return current == next ? nil : next
        }
        if current.uid == buyer.uid {
            return nil
        }
        return joinedBefore(buyer, currentJoin) ? next : nil
    }
}
