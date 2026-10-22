//
//  InMemoryAutoMembers.swift
//  Dokogacha
//
//  UI テスト（`-uiTesting -ui-auto-members`）で、ほかのメンバーの操作を擬似のサーバーの中で自動で返す。
//

import Foundation

/// この端末の人の操作に合わせて、ほかのメンバーの参加・準備OK・引き直しの賛成を擬似のサーバーに送る（06 の §2 の UI テスト）。
///
/// UI テストは 1 台の端末しか操作できないが、06 の §2 の通しのシナリオには 2 人目の参加・全員の準備OK・ほかの人の賛成が要る。
/// 本番の画面に操作を足さずに済むよう、擬似のサーバーのルームの変化を購読し、ほかのメンバーの端末（`InMemoryServer.Device`）から
/// この端末と同じ Callable・直接の書き込みを送る（同じ検証・数え直しを通る）。
///
/// - 自分が作った `open` のルームに自分しかいない → `joiner` が招待コードで参加し、候補を 1 件（`joinerPlace`）投稿する
/// - 自分が準備OKにした `open` のルーム → まだ準備OKでないほかのメンバーが準備OKにする
/// - 投票中の引き直し → まだ投票していないほかのメンバーが賛成する
///
/// 購読は持ち主（`AppDelegate`・テスト）の寿命で止まる（`deinit` で Task を止め、ストリームの `onTermination` で購読が外れる）
final class InMemoryAutoMembers {
    /// 参加してくる人の uid（デモのはるか。`DemoScenario` のデモのメンバーと同じ）
    static let joinerID = "demo-haruka"
    /// 参加してくる人の表示名（プロフィールが無いシナリオ（`first-launch`）では、参加の前に登録する）
    static let joinerName = "はるか"
    /// 参加してくる人が投稿する候補の場所（擬似の検索の明治神宮と同じ）
    static let joinerPlace = Place(
        name: "明治神宮",
        area: "東京・渋谷区",
        latitude: 35.6764,
        longitude: 139.6993,
        mapItemId: "demo-place-meiji"
    )

    /// 購読して返す Task
    private var task: Task<Void, Never>?

    /// `server` のルームの変化を購読し、ほかのメンバーの操作を返し始める
    init(server: InMemoryServer) {
        let updates = server.observe { $0.rooms }
        task = Task { [weak server] in
            for await _ in updates {
                guard let server else {
                    return
                }
                await Self.respond(on: server)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    /// 今の状態を見て、返す操作があれば送る。
    ///
    /// 操作のたびに状態が変わって購読に新しい値が流れるので、1 回で全部を送り切らなくてよい。
    /// 送る前に毎回いまの状態を読み直す（同じ回の前の操作で状態が変わっているため）
    static func respond(on server: InMemoryServer) async {
        guard let me = server.signedInUserID else {
            return
        }
        let roomIDs = server.rooms.filter { $0.value.room.memberIds.contains(me) }.keys.sorted()
        for roomID in roomIDs {
            await joinIfAlone(roomID: roomID, me: me, on: server)
            await followReady(roomID: roomID, me: me, on: server)
            await approveReroll(roomID: roomID, me: me, on: server)
        }
    }

    /// 自分が作った `open` のルームに自分しかいなければ、`joiner` が招待コードで参加して候補を 1 件投稿する。
    ///
    /// 擬似のサーバーは本番と同じく失敗を投げる。ここでの失敗は UI テストの画面の検証で分かるので、投げずに次へ進む
    private static func joinIfAlone(roomID: String, me: String, on server: InMemoryServer) async {
        guard let room = server.rooms[roomID]?.room, room.ownerId == me, room.status == .open, room.memberIds == [me] else {
            return
        }
        let joiner = server.device(of: joinerID)
        if server.users[joinerID] == nil {
            _ = try? await joiner.saveProfile(SaveProfileRequest(displayName: joinerName))
        }
        _ = try? await joiner.joinRoom(JoinRoomRequest(inviteCode: room.inviteCode))
        let request = AddCandidateRequest(
            roomId: roomID,
            place: joinerPlace,
            category: .shrine,
            note: "",
            url: nil,
            fromPastIdeaId: nil
        )
        _ = try? await joiner.addCandidate(request)
    }

    /// 自分が準備OKにした `open` のルームで、まだ準備OKでないほかのメンバーを準備OKにする
    private static func followReady(roomID: String, me: String, on server: InMemoryServer) async {
        guard let record = server.rooms[roomID], record.room.status == .open, record.members[me]?.ready == true else {
            return
        }
        let waiting = record.members.filter { $0.key != me && !$0.value.ready }.keys.sorted()
        for userID in waiting where server.rooms[roomID]?.room.status == .open {
            await server.device(of: userID).setReady(true, roomID: roomID)
        }
    }

    /// 投票中の引き直しに、まだ投票していないほかのメンバーが賛成する（可決したら、残りの人は投票しない）
    private static func approveReroll(roomID: String, me: String, on server: InMemoryServer) async {
        guard let room = server.rooms[roomID]?.room, room.status == .drawn, room.reroll.status == .voting else {
            return
        }
        let voted = Set(room.reroll.votesFor + room.reroll.votesAgainst)
        let others = room.memberIds.filter { $0 != me && !voted.contains($0) }
        for userID in others where server.rooms[roomID]?.room.reroll.status == .voting {
            try? await server.device(of: userID).voteReroll(VoteRerollRequest(roomId: roomID, approve: true))
        }
    }
}
