//
//  InMemoryServer+Purchase.swift
//  Dokogacha
//
//  擬似のサーバーの広告非表示の購入（backend の `purchase/service.ts` の `verifyPurchase`）。
//  署名（App Store の証明書）は確かめず、形だけを確かめて受け付ける。購入者の決め方は `AdFreeSponsorRule`（backend と同じ）。
//

import Foundation

extension InMemoryServer {
    /// 署名付きトランザクションの最大の長さ（backend の `MAX_SIGNED_TRANSACTION_LENGTH`）
    static let maxSignedTransactionLength = 16 * 1_024

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        try verifyPurchase(request, by: signedInUserID)
    }

    /// 広告非表示の購入を記録する（backend の `verifyPurchase`）。
    ///
    /// 表示名の登録の前は `profile-required`、JWS の形でなければ `invalid-argument`。
    /// 参加しているルーム（状態は問わない）の購入者を最初に参加した購入者にそろえてから、`users.adFree` を true にする。何度呼んでも同じ
    func verifyPurchase(_ request: VerifyPurchaseRequest, by callerID: String?) throws -> VerifyPurchaseResponse {
        let userID = try Self.requireCaller(callerID)
        guard Self.isSignedTransactionShaped(request.signedTransaction) else {
            throw Self.error(.invalidArgument)
        }
        guard var profile = users[userID] else {
            throw Self.error(.profileRequired)
        }
        for (roomID, record) in rooms where record.room.memberIds.contains(userID) {
            guard let buyer = record.members[userID] else {
                continue
            }
            let current = record.room.adFreeSponsor
            let currentJoin = current.flatMap { sponsor in
                record.members[sponsor.uid].map { AdFreeSponsorRule.JoinOrder(uid: sponsor.uid, joinedAt: $0.joinedAt) }
            }
            let next = AdFreeSponsorRule.afterPurchase(
                current: current,
                buyer: AdFreeSponsorRule.JoinOrder(uid: userID, joinedAt: buyer.joinedAt),
                buyerName: buyer.displayName,
                currentJoin: currentJoin
            )
            if let next {
                rooms[roomID]?.room.adFreeSponsor = next
            }
        }
        if !profile.adFree {
            profile.adFree = true
            users[userID] = profile
        }
        return VerifyPurchaseResponse(adFree: true)
    }

    /// JWS の形（base64url の 3 つの部分を `.` でつないだもの。backend の `JWS_PATTERN`）で、長すぎないか
    static func isSignedTransactionShaped(_ value: String) -> Bool {
        guard value.utf16.count <= maxSignedTransactionLength else {
            return false
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let isBase64URL = { (part: Substring) in part.unicodeScalars.allSatisfy { allowed.contains($0) } }
        return !parts[0].isEmpty && !parts[1].isEmpty && parts.allSatisfy(isBase64URL)
    }
}
