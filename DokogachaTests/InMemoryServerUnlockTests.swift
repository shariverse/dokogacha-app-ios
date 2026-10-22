//
//  InMemoryServerUnlockTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの準備OKと解禁（backend の `onMemberWrite`・`forceUnlock`・`checkDeadlines`）と、
/// 設定の変更（`updateRoomSettings`・02 の F-03）が、backend と同じ検証・状態遷移をすることを確かめる
/// （backend の `test/emulator/unlock.test.ts`・`settings.test.ts` と同じ観点）
struct InMemoryServerUnlockTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// テストで進められる時計（擬似のサーバーの `clock`）
    final class TestClock {
        var now = InMemoryServerUnlockTests.now
    }

    /// 作成者 "owner" でサインインした擬似のサーバー（時刻は `clock`。乱数は呼ぶたびに 1 つずつ進め、招待コードが重ならないようにする）
    static func makeServer(clock: TestClock = TestClock()) -> InMemoryServer {
        var counter = 0
        var random = 0
        return InMemoryServer(
            clock: { clock.now },
            randomIndex: { upperBound in
                random += 1
                return random % upperBound
            },
            makeID: {
                counter += 1
                return "id-\(counter)"
            },
            signedInUserID: "owner"
        )
    }

    /// "owner" が作ったルームに `others` が参加し、`ready` の人が準備OKにした状態を作る
    static func makeRoom(
        _ server: InMemoryServer,
        rule: UnlockRule = .all,
        deadline: Date? = nil,
        others: [String] = ["bob", "carol"],
        ready: [String] = []
    ) async throws -> String {
        for userID in ["owner"] + others {
            _ = try await server.device(of: userID).saveProfile(SaveProfileRequest(displayName: userID))
        }
        let response = try await server.createRoom(
            CreateRoomRequest(name: "年末の旅行", postLimit: 3, unlockRule: rule, deadline: deadline, likeMode: .boost)
        )
        for userID in others {
            _ = try await server.device(of: userID).joinRoom(JoinRoomRequest(inviteCode: response.inviteCode))
        }
        for userID in ready {
            await server.device(of: userID).setReady(true, roomID: response.roomId)
        }
        return response.roomId
    }

    /// ルームの値
    static func room(_ server: InMemoryServer, _ roomID: String) throws -> Room {
        try #require(server.rooms[roomID]?.room)
    }

    // MARK: onMemberWrite に当たる判定し直し

    /// 全員OK条件で最後の 1 人が準備OKすると `unlocked`、誰かが取り消すと `open` に戻る（F-30〜32 の AC）
    @Test
    func lastReadyUnlocksAndCancelReopens() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["owner", "bob"])
        #expect(try Self.room(server, roomID).status == .open)

        await server.device(of: "carol").setReady(true, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
        #expect(try Self.room(server, roomID).readyCount == 3)

        await server.device(of: "bob").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .open)
        #expect(try Self.room(server, roomID).readyCount == 2)
    }

    /// 過半数OK条件で過半数が準備OKすると `unlocked`、過半数を割ると `open` に戻る
    @Test
    func majorityUnlocksAndFallsBack() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, rule: .majority, others: ["bob", "carol", "dave", "erin"], ready: ["owner", "bob"])
        #expect(try Self.room(server, roomID).status == .open)
        await server.device(of: "carol").setReady(true, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
        await server.device(of: "carol").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .open)
    }

    /// 準備OKの人の退出・メンバーの削除で数え直して判定し直す
    @Test
    func leaveAndRemoveRecount() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, others: ["bob", "carol", "dave"], ready: ["bob", "carol"])
        try await server.device(of: "bob").leaveRoom(RoomRequest(roomId: roomID))
        #expect(try Self.room(server, roomID).memberCount == 3)
        #expect(try Self.room(server, roomID).readyCount == 1)
        #expect(try Self.room(server, roomID).status == .open)

        await server.device(of: "owner").setReady(true, roomID: roomID)
        try await server.removeMember(RemoveMemberRequest(roomId: roomID, memberId: "dave"))
        #expect(try Self.room(server, roomID).memberCount == 2)
        #expect(try Self.room(server, roomID).readyCount == 2)
        #expect(try Self.room(server, roomID).status == .unlocked)
    }

    /// 解禁済みのルームに新しい人が参加すると `open` に戻る（F-04「解禁条件を再計算する」）
    @Test
    func joinReopensUnlockedRoom() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, others: ["bob"], ready: ["owner", "bob"])
        #expect(try Self.room(server, roomID).status == .unlocked)
        _ = try await server.device(of: "carol").saveProfile(SaveProfileRequest(displayName: "carol"))
        let code = try Self.room(server, roomID).inviteCode
        _ = try await server.device(of: "carol").joinRoom(JoinRoomRequest(inviteCode: code))
        #expect(try Self.room(server, roomID).status == .open)
        #expect(try Self.room(server, roomID).memberCount == 3)
    }

    /// 引き直しが可決して `unlocked` に戻ったルームは、取り消しても `open` に戻さない（02 の §6.4「準備OKはやり直さない」）
    @Test
    func rerolledRoomStaysUnlocked() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["owner", "bob", "carol"])
        server.rooms[roomID]?.room.reroll.status = .passed
        await server.device(of: "carol").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
        #expect(try Self.room(server, roomID).readyCount == 2)
    }

    /// `lastSeenAt` だけの書き込みでは判定し直さない（backend の `memberWriteAffectsUnlock`）
    @Test
    func markSeenDoesNotRejudge() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        server.rooms[roomID]?.room.status = .unlocked
        await server.device(of: "bob").markSeen(roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
    }

    // MARK: forceUnlock（F-32）

    /// 作成者が強制解禁すると、準備OKが 0 人でも `unlocked` になり、取り消し・参加があっても戻らない
    @Test
    func forceUnlockStaysUnlocked() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["bob"])
        try await server.forceUnlock(RoomRequest(roomId: roomID))
        #expect(try Self.room(server, roomID).status == .unlocked)
        #expect(try Self.room(server, roomID).forcedUnlock)

        await server.device(of: "bob").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
        _ = try await server.device(of: "dave").saveProfile(SaveProfileRequest(displayName: "dave"))
        let code = try Self.room(server, roomID).inviteCode
        _ = try await server.device(of: "dave").joinRoom(JoinRoomRequest(inviteCode: code))
        #expect(try Self.room(server, roomID).status == .unlocked)
    }

    /// 作成者以外は強制解禁できない
    @Test
    func forceUnlockRequiresOwner() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        await #expect(throws: InMemoryServer.error(.notRoomOwner)) {
            try await server.device(of: "bob").forceUnlock(RoomRequest(roomId: roomID))
        }
        #expect(try Self.room(server, roomID).status == .open)
    }

    /// もう `unlocked` なら何もせずに成功する（`forcedUnlock` は立てない）
    @Test
    func forceUnlockOnUnlockedRoomDoesNothing() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["owner", "bob", "carol"])
        try await server.forceUnlock(RoomRequest(roomId: roomID))
        #expect(try Self.room(server, roomID).forcedUnlock == false)
        await server.device(of: "bob").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .open)
    }

    /// `drawn`・`closed` では強制解禁できない。ルームが無ければ `room-not-found`
    @Test(arguments: [RoomStatus.drawn, .closed])
    func forceUnlockRejectsDecidedRoom(status: RoomStatus) async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        server.rooms[roomID]?.room.status = status
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            try await server.forceUnlock(RoomRequest(roomId: roomID))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.forceUnlock(RoomRequest(roomId: "nothing"))
        }
    }

    // MARK: checkDeadlines（擬似のサーバーの時刻で判定する）

    /// 締切日時を過ぎた `open` のルームだけを `unlocked` にする。締切で解禁した後は取り消しても戻らない
    @Test
    func checkDeadlinesUnlocksPassedRooms() async throws {
        let clock = TestClock()
        let server = Self.makeServer(clock: clock)
        let deadline = Self.now.addingTimeInterval(2 * 3_600)
        let roomID = try await Self.makeRoom(server, rule: .deadline, deadline: deadline, ready: ["bob"])
        let otherID = try await Self.makeRoom(server)

        clock.now = deadline.addingTimeInterval(-1)
        #expect(server.checkDeadlines() == 0)
        #expect(try Self.room(server, roomID).status == .open)

        clock.now = deadline
        #expect(server.checkDeadlines() == 1)
        #expect(try Self.room(server, roomID).status == .unlocked)
        #expect(try Self.room(server, otherID).status == .open)
        #expect(server.checkDeadlines() == 0)

        await server.device(of: "bob").setReady(false, roomID: roomID)
        #expect(try Self.room(server, roomID).status == .unlocked)
    }

    // MARK: updateRoomSettings（F-03）

    /// 作成者は `open` のルームのすべての項目を変えられる。締切日時から別の条件にすると締切日時を消す
    @Test
    func updateAllSettingsWhenOpen() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        let deadline = Self.now.addingTimeInterval(2 * 3_600)
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(
            roomId: roomID,
            name: " 春の旅行 ",
            postLimit: 5,
            unlockRule: .deadline,
            deadlineAt: CallableTime.milliseconds(from: deadline),
            likeMode: .equal
        ))
        let room = try Self.room(server, roomID)
        #expect(room.name == "春の旅行")
        #expect(room.settings == RoomSettings(postLimit: 5, unlockRule: .deadline, deadlineAt: deadline, likeMode: .equal))

        try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, unlockRule: .all))
        #expect(try Self.room(server, roomID).settings.deadlineAt == nil)
        #expect(try Self.room(server, roomID).settings.unlockRule == .all)
    }

    /// 条件を変えたら解禁を判定し直す（全員OK → 過半数OK で、すでに過半数が準備OKなら `unlocked`）
    @Test
    func changingRuleRejudges() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["owner", "bob"])
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, unlockRule: .majority))
        #expect(try Self.room(server, roomID).status == .unlocked)
    }

    /// 作成者以外は変えられない・`closed` では何も変えられない・ルームが無ければ `room-not-found`
    @Test
    func updateRequiresOwnerAndNotClosed() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        await #expect(throws: InMemoryServer.error(.notRoomOwner)) {
            try await server.device(of: "bob").updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, name: "乗っ取り"))
        }
        server.rooms[roomID]?.room.status = .closed
        await #expect(throws: InMemoryServer.error(.roomClosed)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, name: "春"))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: "nothing", name: "春"))
        }
        #expect(try Self.room(server, roomID).name == "年末の旅行")
    }

    /// 投稿数は引き上げのみ（同じ値は変えない）
    @Test
    func postLimitCanOnlyIncrease() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        await #expect(throws: InMemoryServer.error(.postLimitDecrease)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, postLimit: 2))
        }
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, postLimit: 3))
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, postLimit: 4))
        #expect(try Self.room(server, roomID).settings.postLimit == 4)
    }

    /// `unlocked` ではルーム名・投稿数・いいねの効き方を変えられ、解禁の条件は変えられない（同じ値を送っただけなら断らない）
    @Test
    func unlockedRoomLocksUnlockRule() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, ready: ["owner", "bob", "carol"])
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(
            roomId: roomID, name: "春", postLimit: 4, unlockRule: .all, likeMode: .equal
        ))
        let room = try Self.room(server, roomID)
        #expect(room.name == "春")
        #expect(room.settings.postLimit == 4)
        #expect(room.settings.likeMode == .equal)
        #expect(room.status == .unlocked)
        await #expect(throws: InMemoryServer.error(.unlockRuleLocked)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, unlockRule: .majority))
        }
    }

    /// `drawn` ではルーム名と投稿数だけを変えられる
    @Test
    func drawnRoomLocksLikeModeAndRule() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        server.rooms[roomID]?.room.status = .drawn
        try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, name: "春", postLimit: 4))
        #expect(try Self.room(server, roomID).name == "春")
        await #expect(throws: InMemoryServer.error(.likeModeLocked)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, likeMode: .equal))
        }
        await #expect(throws: InMemoryServer.error(.unlockRuleLocked)) {
            try await server.updateRoomSettings(UpdateRoomSettingsRequest(roomId: roomID, unlockRule: .majority))
        }
        #expect(try Self.room(server, roomID).status == .drawn)
    }

    /// 入力が正しくないものは `invalid-argument`（backend の `parseUpdateRoomSettingsInput`・`planUnlockRule` と同じ）
    @Test(arguments: [
        // ルーム名が空・投稿数が範囲の外
        UpdateRoomSettingsRequest(roomId: "R", name: "  "),
        UpdateRoomSettingsRequest(roomId: "R", postLimit: 11),
        // 締切日時の条件なのに締切日時が無い・締切日時以外の条件に締切日時・今の条件が締切日時でないのに締切日時だけ
        UpdateRoomSettingsRequest(roomId: "R", unlockRule: .deadline),
        UpdateRoomSettingsRequest(
            roomId: "R", unlockRule: .all, deadlineAt: CallableTime.milliseconds(from: now.addingTimeInterval(7_200))
        ),
        UpdateRoomSettingsRequest(roomId: "R", deadlineAt: CallableTime.milliseconds(from: now.addingTimeInterval(7_200))),
        // 締切日時が今から 1 時間後（5 分の猶予）より前・30 日後より後
        UpdateRoomSettingsRequest(
            roomId: "R", unlockRule: .deadline, deadlineAt: CallableTime.milliseconds(from: now.addingTimeInterval(54 * 60))
        ),
        UpdateRoomSettingsRequest(
            roomId: "R", unlockRule: .deadline, deadlineAt: CallableTime.milliseconds(from: now.addingTimeInterval(31 * 86_400))
        )
    ])
    func updateRejectsInvalidInput(request: UpdateRoomSettingsRequest) async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server)
        var request = request
        request.roomId = roomID
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await server.updateRoomSettings(request)
        }
        #expect(try Self.room(server, roomID).settings == RoomSettings(postLimit: 3, unlockRule: .all, deadlineAt: nil, likeMode: .boost))
    }

    /// 締切日時のままなら、締切日時だけを変えられる（条件は送らなくてよい）
    @Test
    func deadlineCanChangeAlone() async throws {
        let server = Self.makeServer()
        let roomID = try await Self.makeRoom(server, rule: .deadline, deadline: Self.now.addingTimeInterval(7_200))
        let later = Self.now.addingTimeInterval(86_400)
        try await server.updateRoomSettings(
            UpdateRoomSettingsRequest(roomId: roomID, deadlineAt: CallableTime.milliseconds(from: later))
        )
        #expect(try Self.room(server, roomID).settings.deadlineAt == later)
        #expect(try Self.room(server, roomID).settings.unlockRule == .deadline)
    }
}
