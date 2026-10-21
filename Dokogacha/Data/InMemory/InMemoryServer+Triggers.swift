//
//  InMemoryServer+Triggers.swift
//  Dokogacha
//
//  擬似のサーバーの Firestore のトリガー（backend の `onUserProfileUpdate` など）に当たる処理。
//  backend ではドキュメントの更新の後に非同期で動くが、擬似のサーバーでは更新した Callable の中で続けて行う。
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
}
