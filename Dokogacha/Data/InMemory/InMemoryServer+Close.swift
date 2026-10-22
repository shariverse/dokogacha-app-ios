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
    /// → 状態（`drawn` なら終了・`closed` なら何もしない・`open`・`unlocked` は `room-not-drawn`）の順に確かめる。
    /// 終了したら、当選しなかった候補を各メンバーの過去のアイデアに登録する
    func closeRoom(_ request: RoomRequest, by callerID: String?) throws {
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
        switch record.room.status {
        case .drawn:
            break
        case .closed:
            return
        case .open, .unlocked:
            throw Self.error(.roomNotDrawn)
        }
        record.room.status = .closed
        record.room.closedAt = clock()
        rooms[roomID] = record
        registerPastIdeas(roomID: roomID)
    }

    /// 終了したルームの過去のアイデアを登録する（backend の `registerPastIdeas`。`closed` でなければ何もしない。何度呼んでも同じ値）
    func registerPastIdeas(roomID: String) {
        guard let record = rooms[roomID], record.room.status == .closed else {
            return
        }
        let writes = RoomClosing.pastIdeas(roomID: roomID, room: record.room, candidates: record.candidates, closedAt: clock())
        var updated = pastIdeas
        for write in writes {
            updated[write.userID, default: [:]][write.ideaID] = write.idea
        }
        pastIdeas = updated
    }
}
