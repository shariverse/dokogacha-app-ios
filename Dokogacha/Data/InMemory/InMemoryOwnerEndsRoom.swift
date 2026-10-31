//
//  InMemoryOwnerEndsRoom.swift
//  Dokogacha
//
//  UI テスト（`-uiTesting -ui-owner-ends-room`）で、ほかの人が作ったルームを、その作成者が途中で終了したことにする。
//

import Foundation

/// ほかの人が作った候補募集中・ガチャ解禁！のルームで、この端末の人が準備OKにしたら、作成者がルームを途中で終了する
/// （`closeRoom` の `endEarly`。Discussion #155 の、開いている間にほかの人が終了したときの画面の UI テスト）。
///
/// UI テストは 1 台の端末しか操作できないので、`InMemoryAutoMembers` と同じく擬似のサーバーのルームの変化を購読し、
/// 作成者の uid で同じ Callable を呼ぶ（同じ検証を通る）。きっかけを「準備OK」にしたのは、S-07 を開いた後に
/// この端末の人が押すまで終了しないので、S-07 が開いている間に終了したことを確かめられるため。
/// 購読は持ち主（`AppDelegate`）の寿命で止まる
final class InMemoryOwnerEndsRoom {
    /// 購読して返す Task
    private var task: Task<Void, Never>?

    /// `server` のルームの変化を購読し始める
    init(server: InMemoryServer) {
        let updates = server.observe { $0.rooms }
        task = Task { [weak server] in
            for await _ in updates {
                guard let server else {
                    return
                }
                Self.respond(on: server)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    /// 自分が準備OKにした、ほかの人が作った `open`・`unlocked` のルームを、作成者が途中で終了する
    static func respond(on server: InMemoryServer) {
        guard let me = server.signedInUserID else {
            return
        }
        let targets = server.rooms.filter { _, record in
            record.room.ownerId != me && RoomClosing.endableStatuses.contains(record.room.status)
                && record.members[me]?.ready == true
        }
        for (roomID, record) in targets.sorted(by: { $0.key < $1.key }) {
            // 失敗は UI テストの画面の検証で分かるので、投げずに次へ進む
            try? server.closeRoom(CloseRoomRequest(roomId: roomID, reason: .endEarly), by: record.room.ownerId)
        }
    }
}
