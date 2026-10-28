//
//  InMemoryServer+Triggers.swift
//  Dokogacha
//
//  擬似のサーバーの Firestore のトリガー（backend の `onUserProfileUpdate`・`onMemberWrite`）とスケジュール（`checkDeadlines`）に当たる処理。
//  backend ではドキュメントの更新の後に非同期で動くが、擬似のサーバーでは更新した Callable・直接の書き込みの中で続けて行う。
//

import Foundation

extension InMemoryServer {
    /// プロフィールの表示名・アバターの色を、参加中のルームの複製に反映する（backend の `users/profileSync.ts` の `syncProfileCopies`）。
    ///
    /// 参加中のルーム（`memberIds` に自分がいて、メンバーのドキュメントがある。状態は問わない）ごとに、
    /// メンバーの `displayName`・`avatarColor`、自分の候補の `postedByName`、自分が購入者なら `adFreeSponsor.displayName` を今の値にする。
    /// 抽選の記録（`drawnByName`）は回したときの値を残す。今の値と同じものは書き換えない（何度呼んでも同じ結果）
    func syncProfileCopies(of userID: String) {
        guard let profile = users[userID] else {
            return
        }
        var updated = rooms
        for (roomID, record) in rooms {
            guard record.room.memberIds.contains(userID), record.members[userID] != nil else {
                continue
            }
            var next = record
            next.members[userID]?.displayName = profile.displayName
            next.members[userID]?.avatarColor = profile.avatarColor
            for (candidateID, candidate) in record.candidates where candidate.postedBy == userID {
                next.candidates[candidateID]?.postedByName = profile.displayName
            }
            if record.room.adFreeSponsor?.uid == userID {
                next.room.adFreeSponsor = AdFreeSponsor(uid: userID, displayName: profile.displayName)
            }
            if next != record {
                updated[roomID] = next
            }
        }
        // 購読に 1 回だけ流すよう、まとめて入れ替える（変わっていなければ入れ替えない）
        if updated != rooms {
            rooms = updated
        }
    }

    /// メンバーを数え直して、解禁の条件（F-31）で `open`⇄`unlocked` を判定し直す
    /// （backend の `onMemberWrite`・`unlock/logic.ts` の `planUnlock`。今の時刻は `clock`）。
    ///
    /// メンバーの参加・退出・削除・準備OKの変更と、設定の変更の後に呼ぶ（backend と同じく `lastSeenAt` だけの更新では呼ばない）。
    /// - `memberCount`・`readyCount` はメンバーから数え直す（増減ではない）。判定には数え直した値を使う
    /// - `drawn`・`closed` は状態を変えない
    /// - 引き直しが可決して `unlocked` に戻ったルームは、準備OKの数で `open` に戻さない（02 の §6.4「準備OKはやり直さない」）
    func rejudgeUnlock(_ record: inout RoomRecord) {
        record.room.memberCount = record.members.count
        record.room.readyCount = record.members.values.filter(\.ready).count
        let status = record.room.status
        guard status == .open || status == .unlocked else {
            return
        }
        if status == .unlocked, record.room.reroll.status == .passed {
            return
        }
        let input = UnlockInput(
            status: status,
            rule: record.room.settings.unlockRule,
            memberCount: record.room.memberCount,
            readyCount: record.room.readyCount,
            deadlineAt: record.room.settings.deadlineAt,
            forcedUnlock: record.room.forcedUnlock
        )
        record.room.status = UnlockJudge.nextStatus(input, now: clock())
    }

    /// 締切日時を過ぎた `open` のルームを判定し直して `unlocked` にする（backend の `checkDeadlines`。5 分ごとのスケジュール）。
    ///
    /// 擬似のサーバーには時刻で動く仕組みが無いので、テスト・デモで時刻（`clock`）を進めた後に呼ぶ。
    /// - Returns: 解禁したルームの数
    @discardableResult
    func checkDeadlines() -> Int {
        let now = clock()
        var updated = rooms
        var unlocked = 0
        for (roomID, record) in rooms {
            guard record.room.status == .open, let deadlineAt = record.room.settings.deadlineAt, deadlineAt <= now else {
                continue
            }
            var next = record
            rejudgeUnlock(&next)
            if next.room.status == .unlocked {
                unlocked += 1
            }
            if next != record {
                updated[roomID] = next
            }
        }
        // 購読に 1 回だけ流すよう、まとめて入れ替える（変わっていなければ入れ替えない）
        if updated != rooms {
            rooms = updated
        }
        return unlocked
    }
}
