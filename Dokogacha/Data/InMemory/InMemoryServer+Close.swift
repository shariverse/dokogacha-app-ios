//
//  InMemoryServer+Close.swift
//  Dokogacha
//
//  擬似のサーバーのルームの終了（backend の `close/service.ts` の `closeRoom` と、`onRoomClosed` の過去のアイデアの登録）。
//  backend の `close/logic.ts` の `decideClose` と同じ順で検証し、同じ理由で失敗する（`InMemoryServerCloseTests` で確かめる）。
//  backend では終了の後にトリガーが過去のアイデアを書くが、擬似のサーバーは同じ呼び出しの中で書く（`RoomClosing.pastIdeas` と同じ規則）。
//

import Foundation

extension InMemoryServer {
    /// ルームを終了する（backend の `closeRoom`）。呼んだ人の uid を `callerID` で受け取る（ほかのメンバーの端末 `Device` からも呼ぶ）。
    ///
    /// 入力の検証 → ルーム（無ければ `room-not-found`）→ メンバーか（`not-room-member`）→ 作成者か（`not-room-owner`）
    /// → 状態と意図（`RoomClosing.decision`。`closed` なら何もしない・`decide` は `drawn` だけ（違えば `room-not-drawn`）・
    /// `endEarly` は `open`・`unlocked` だけ（`drawn` は `room-already-decided`））の順に確かめる。
    /// 引き直しの投票中なら、終了と同時に否決にする（backend の `rerollUpdateOnClose`。投票中のまま残すと `expireRerolls` が
    /// 終了したルームを後から書き換える）。終了したら、当選しなかった候補を各メンバーの過去のアイデアに登録する
    func closeRoom(_ request: CloseRoomRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.memberIds.contains(userID) else {
            throw Self.error(.notRoomMember)
        }
        guard record.room.ownerId == userID else {
            throw Self.error(.notRoomOwner)
        }
        switch RoomClosing.decision(status: record.room.status, reason: request.reason) {
        case .close:
            break
        case .alreadyClosed:
            return
        case .reject(let reason):
            throw Self.error(reason)
        }
        record.room.status = .closed
        record.room.closedAt = clock()
        if record.room.reroll.status == .voting {
            record.room.reroll.status = .rejected
        }
        rooms[roomID] = record
        registerPastIdeas(roomID: roomID)
    }

    /// 終了したルームの過去のアイデアを登録する（backend の `registerPastIdeas`。`closed` でなければ何もしない。何度呼んでも同じ値）。
    ///
    /// backend と同じく、`users/{uid}` が無い人（アカウントを削除した人）には登録しない
    func registerPastIdeas(roomID: String) {
        guard let record = rooms[roomID], record.room.status == .closed else {
            return
        }
        let writes = RoomClosing.pastIdeas(roomID: roomID, room: record.room, candidates: record.candidates, closedAt: clock())
        var updated = pastIdeas
        for write in writes where users[write.userID] != nil {
            updated[write.userID, default: [:]][write.ideaID] = write.idea
        }
        pastIdeas = updated
    }
}
