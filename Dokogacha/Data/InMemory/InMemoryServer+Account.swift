//
//  InMemoryServer+Account.swift
//  Dokogacha
//
//  擬似のサーバーのアカウントの削除（backend の `account/service.ts` の `deleteAccount`。02 の §2.6 F-06）。
//  参加中のルームごとに何をするかは `AccountDeletion`（backend の `account/logic.ts` と同じ規則）で決める。
//  backend では作成者のルームの終了の後にトリガーが過去のアイデアを書くが、擬似のサーバーは同じ呼び出しの中で書く。
//

import Foundation

extension InMemoryServer {
    /// 呼んだ人のアカウントを削除する（backend の `deleteAccount`）。呼んだ人の uid を `callerID` で受け取る（ほかのメンバーの端末 `Device` からも呼ぶ）。
    ///
    /// 1. 参加中のルーム（状態は問わない）から、退出と同じ処理で外す（いいねの取り消し・購入者の付け替え・引き直しの投票の判定し直し）。
    ///    作成者で終了していないルームは、終了（`closed`。投票中の引き直しは否決）してから外し、残るメンバーに過去のアイデアを登録する
    /// 2. `users/{uid}`（表示名・通知のトークン・広告非表示の購入）と過去のアイデアを消す
    /// 3. Auth のユーザーを消す（Sign in with Apple の連携も外れる）。この端末のサインインはそのまま（アプリが `signOut` で外す。
    ///    Firebase でも、サーバーで消されたユーザーのサインインは、端末のトークンが切れるまで残る）
    ///
    /// 候補（`postedBy`・`postedByName`）・抽選の記録・投稿の報告・作成者のルームの `ownerId` は残す。何度呼んでも同じ結果になる
    func deleteAccount(by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        for roomID in rooms.keys.sorted() {
            guard var record = rooms[roomID] else {
                continue
            }
            let action = AccountDeletion.action(for: record.room, userID: userID)
            switch action {
            case .none:
                continue
            case .leave:
                break
            case .closeAndLeave:
                record.room.status = .closed
                record.room.closedAt = clock()
                if record.room.reroll.status == .voting {
                    record.room.reroll.status = .rejected
                }
            }
            if record.members[userID] != nil {
                try remove(userID, from: &record, notMember: .memberNotFound)
            } else {
                // メンバーのドキュメントが無い壊れたデータでも、`memberIds` から外す（backend の `notMember: null`）
                record.room.memberIds.removeAll { $0 == userID }
                rejudgeUnlock(&record)
            }
            rooms[roomID] = record
            if action == .closeAndLeave {
                registerPastIdeas(roomID: roomID)
            }
        }
        users[userID] = nil
        pastIdeas[userID] = nil
        appleAccounts = appleAccounts.filter { $0.value != userID }
        deletedUserIDs.insert(userID)
    }

    /// サインインしている人を、アカウントの削除で消したか（Firebase の `reload` が userNotFound で失敗するのと同じ）
    func isCurrentAccountDeleted() async -> Bool {
        guard let signedInUserID else {
            return false
        }
        return deletedUserIDs.contains(signedInUserID)
    }
}
