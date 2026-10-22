//
//  PurchaseRulesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 広告非表示の買い切り（02 の §7.2 F-51・05 の §8）の判定を確かめる。
/// ルームの購入者の決め方は backend の `functions/src/purchase/logic.test.ts` の `sponsorAfterPurchase` と同じケース
struct PurchaseRulesTests {
    nonisolated private static let purchase = SignedPurchase(productID: "remove_ads", transactionID: "1", signedTransaction: "a.b.c")
    nonisolated private static let base = Date(timeIntervalSince1970: 1_760_000_000)

    private static func join(_ uid: String, _ seconds: TimeInterval) -> AdFreeSponsorRule.JoinOrder {
        AdFreeSponsorRule.JoinOrder(uid: uid, joinedAt: base.addingTimeInterval(seconds))
    }

    private static func room(sponsor: AdFreeSponsor?) -> Room {
        var room = RoomClosingTests.room(.open)
        room.adFreeSponsor = sponsor
        return room
    }

    // MARK: AdFreeStatus

    /// サーバーの記録か端末の購入のどちらかがあれば、自分を広告非表示にする（購入者本人は全画面で広告が消える）
    @Test(arguments: [(false, false, false), (true, false, true), (false, true, true), (true, true, true)])
    func adFreeIfServerOrDeviceHasPurchase(serverAdFree: Bool, hasEntitlement: Bool, expected: Bool) {
        #expect(AdFreeStatus.isAdFree(serverAdFree: serverAdFree, hasEntitlement: hasEntitlement) == expected)
    }

    // MARK: PurchaseVerificationPolicy

    /// 端末に購入があり、サーバーがまだ記録していなければ送る（05 の §8「初回のみ」）
    @Test
    func verifiesWhenDeviceHasPurchaseAndServerDoesNot() {
        #expect(PurchaseVerificationPolicy.shouldVerify(entitlement: Self.purchase, serverAdFree: false, sentTransactionIDs: []))
    }

    /// 購入が無い・プロフィールがまだ読めていない・サーバーが記録済み・この起動で送り済みなら送らない
    @Test
    func doesNotVerifyOtherwise() {
        #expect(!PurchaseVerificationPolicy.shouldVerify(entitlement: nil, serverAdFree: false, sentTransactionIDs: []))
        #expect(!PurchaseVerificationPolicy.shouldVerify(entitlement: Self.purchase, serverAdFree: nil, sentTransactionIDs: []))
        #expect(!PurchaseVerificationPolicy.shouldVerify(entitlement: Self.purchase, serverAdFree: true, sentTransactionIDs: []))
        #expect(!PurchaseVerificationPolicy.shouldVerify(entitlement: Self.purchase, serverAdFree: false, sentTransactionIDs: ["1"]))
        // 別のトランザクション（復元・買い直し）なら送り直す
        #expect(PurchaseVerificationPolicy.shouldVerify(entitlement: Self.purchase, serverAdFree: false, sentTransactionIDs: ["2"]))
    }

    // MARK: AdFreeNoticePolicy

    /// 購入者がいるルームの画面に、購入者の名前で出す（03 の S-07）。購入者本人が開いたときも出す
    @Test
    func noticeShowsSponsorNameOnRoom() {
        let haruka = Self.room(sponsor: AdFreeSponsor(uid: "demo-haruka", displayName: "はるか"))
        #expect(AdFreeNoticePolicy.sponsorName(screen: .room, room: haruka) == "はるか")
        let mine = Self.room(sponsor: AdFreeSponsor(uid: DemoScenario.myUserID, displayName: "たくみ"))
        #expect(AdFreeNoticePolicy.sponsorName(screen: .room, room: mine) == "たくみ")
    }

    /// 購入者がいない・ルームがまだ届いていない・名前が空・ルーム以外の画面では出さない
    @Test(arguments: AdScreen.allCases.filter { $0 != .room })
    func noticeOnlyOnRoomWithSponsor(screen: AdScreen) {
        let sponsored = Self.room(sponsor: AdFreeSponsor(uid: "demo-haruka", displayName: "はるか"))
        #expect(AdFreeNoticePolicy.sponsorName(screen: screen, room: sponsored) == nil)
        #expect(AdFreeNoticePolicy.sponsorName(screen: .room, room: Self.room(sponsor: nil)) == nil)
        #expect(AdFreeNoticePolicy.sponsorName(screen: .room, room: nil) == nil)
        let blank = Self.room(sponsor: AdFreeSponsor(uid: "demo-haruka", displayName: " "))
        #expect(AdFreeNoticePolicy.sponsorName(screen: .room, room: blank) == nil)
    }

    // MARK: AdFreeSponsorRule（backend の sponsorAfterPurchase と同じケース）

    @Test
    func joinedBeforeUsesDateThenUserID() {
        #expect(AdFreeSponsorRule.joinedBefore(Self.join("b", 1), Self.join("a", 2)))
        #expect(!AdFreeSponsorRule.joinedBefore(Self.join("a", 2), Self.join("b", 1)))
        #expect(AdFreeSponsorRule.joinedBefore(Self.join("a", 5), Self.join("b", 5)))
        #expect(!AdFreeSponsorRule.joinedBefore(Self.join("b", 5), Self.join("a", 5)))
    }

    @Test
    func sponsorAfterPurchase() {
        let buyer = Self.join("bob", 200)
        let bob = AdFreeSponsor(uid: "bob", displayName: "ぼぶ")
        func after(_ current: AdFreeSponsor?, _ currentJoin: AdFreeSponsorRule.JoinOrder?) -> AdFreeSponsor? {
            AdFreeSponsorRule.afterPurchase(current: current, buyer: buyer, buyerName: "ぼぶ", currentJoin: currentJoin)
        }
        // 購入者がいなければ、購入した人にする
        #expect(after(nil, nil) == bob)
        // 先に参加した購入者がいれば変えない
        #expect(after(AdFreeSponsor(uid: "alice", displayName: "ありす"), Self.join("alice", 100)) == nil)
        // 購入した人のほうが先に参加していれば、購入した人に替える
        #expect(after(AdFreeSponsor(uid: "carol", displayName: "きゃろる"), Self.join("carol", 300)) == bob)
        // 同じ日時なら uid の小さい方
        #expect(after(AdFreeSponsor(uid: "carol", displayName: "きゃろる"), Self.join("carol", 200)) == bob)
        #expect(after(AdFreeSponsor(uid: "amy", displayName: "えいみー"), Self.join("amy", 200)) == nil)
        // すでに購入した人が購入者なら変えない
        #expect(after(bob, Self.join("bob", 200)) == nil)
        #expect(after(bob, nil) == nil)
        // いまの購入者のメンバーのドキュメントが無ければ、購入した人にする
        #expect(after(AdFreeSponsor(uid: "gone", displayName: "いない人"), nil) == bob)
    }
}
