//
//  InMemoryServerTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーが、backend の Callable と同じ検証・状態遷移をすることを確かめる（Emulator のテストと同じ観点）
struct InMemoryServerTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: saveProfile

    @Test
    func saveProfileCreatesThenRenames() async throws {
        let server = Self.makeServer { _ in 1 }
        let created = try await server.saveProfile(SaveProfileRequest(displayName: "  たくみ "))
        #expect(created == SaveProfileResponse(displayName: "たくみ", avatarColor: AvatarPalette.colors[1], created: true))
        let renamed = try await server.saveProfile(SaveProfileRequest(displayName: "たくみ2"))
        #expect(renamed.created == false)
        #expect(renamed.avatarColor == AvatarPalette.colors[1])
        #expect(server.users["owner"]?.displayName == "たくみ2")
        #expect(server.users["owner"]?.adFree == false)
    }

    /// 見えない文字が混ざっていても、見える文字があれば受け付ける（ZWJ の絵文字など）
    @Test
    func saveProfileAcceptsVisibleNameWithFormatCharacters() async throws {
        let response = try await Self.makeServer().saveProfile(SaveProfileRequest(displayName: "👨‍👩‍👧たくみ"))
        #expect(response.displayName == "👨‍👩‍👧たくみ")
    }

    /// 結合文字を重ねた 1 文字は、UTF-16 の上限（表示名は 10 × 16 = 160 単位）までなら受け付ける（backend と同じ境目）
    @Test
    func saveProfileAcceptsCombiningMarksUpToUTF16Limit() async throws {
        let atLimit = "e" + String(repeating: "\u{0301}", count: 159)
        let response = try await Self.makeServer().saveProfile(SaveProfileRequest(displayName: atLimit))
        #expect(response.displayName == atLimit)
    }

    /// 空・長すぎる・途中に改行や制御文字や行区切り・見えない文字だけ・UTF-16 の上限を超えた名前は拒む（判定は `NameValidation`）
    @Test(arguments: [
        "", "   ", "12345678901", "た\nくみ", "た\u{07}くみ", "た\u{2028}くみ", "\u{200B}\u{2060}", "\u{FEFF}",
        "\u{200B} \u{200B}", "\u{3164}", "\u{FE0F}",
        "e" + String(repeating: "\u{0301}", count: 160)
    ])
    func saveProfileRejectsInvalidName(name: String) async {
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await Self.makeServer().saveProfile(SaveProfileRequest(displayName: name))
        }
    }

    @Test
    func callablesRequireSignIn() async {
        let server = Self.makeServer()
        server.signedInUserID = nil
        await #expect(throws: InMemoryServer.error(.unauthenticated)) {
            try await server.saveProfile(SaveProfileRequest(displayName: "a"))
        }
    }

    // MARK: createRoom

    /// F-02 の AC「作成直後のルームは open、メンバーは作成者1人」
    @Test
    func createRoomStartsOpenWithOwnerOnly() async throws {
        let server = Self.makeServer()
        let response = try await Self.makeRoom(server)
        let record = try #require(server.rooms[response.roomId])
        #expect(record.room.status == .open)
        #expect(record.room.memberIds == ["owner"])
        #expect(record.room.memberCount == 1)
        #expect(record.room.inviteCode == response.inviteCode)
        #expect(record.members["owner"]?.role == .owner)
        #expect(record.members["owner"]?.ready == false)
        #expect(record.members["owner"]?.lastSeenAt == Self.now)
        #expect(server.inviteCodes[response.inviteCode]?.roomId == response.roomId)
        #expect(InviteCode(response.inviteCode) != nil)
    }

    @Test
    func createRoomRequiresProfile() async {
        await #expect(throws: InMemoryServer.error(.profileRequired)) {
            try await Self.makeServer().createRoom(Self.simpleRoom())
        }
    }

    @Test(arguments: [
        CreateRoomRequest(name: "", postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost),
        CreateRoomRequest(name: String(repeating: "あ", count: 21), postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost),
        // ルーム名の UTF-16 の上限は 20 × 16 = 320 単位
        CreateRoomRequest(
            name: "e" + String(repeating: "\u{0301}", count: 320), postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost
        ),
        CreateRoomRequest(name: "a", postLimit: 0, unlockRule: .all, deadline: nil, likeMode: .boost),
        CreateRoomRequest(name: "a", postLimit: 11, unlockRule: .all, deadline: nil, likeMode: .boost),
        CreateRoomRequest(name: "a", postLimit: 3, unlockRule: .deadline, deadline: nil, likeMode: .boost),
        CreateRoomRequest(name: "a", postLimit: 3, unlockRule: .deadline, deadline: now.addingTimeInterval(30 * 60), likeMode: .boost),
        CreateRoomRequest(name: "a", postLimit: 3, unlockRule: .deadline, deadline: now.addingTimeInterval(31 * 86_400), likeMode: .boost)
    ])
    func createRoomRejectsInvalidInput(request: CreateRoomRequest) async throws {
        let server = Self.makeServer()
        try await Self.addUser(server, "owner")
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await server.createRoom(request)
        }
    }

    @Test
    func createRoomAcceptsDeadlineWithinRange() async throws {
        let server = Self.makeServer()
        try await Self.addUser(server, "owner")
        let deadline = Self.now.addingTimeInterval(3 * 86_400)
        let response = try await server.createRoom(
            CreateRoomRequest(name: "a", postLimit: 3, unlockRule: .deadline, deadline: deadline, likeMode: .equal)
        )
        #expect(server.rooms[response.roomId]?.room.settings.deadlineAt == deadline)
    }

    /// 招待コードが使用済みなら作り直す。続けて重なれば invite-code-unavailable
    @Test
    func createRoomRegeneratesDuplicateInviteCode() async throws {
        var calls = 0
        // 最初の 6 文字は 0（AAAAAA）、次の 6 文字は 1（BBBBBB）
        let server = Self.makeServer { _ in
            calls += 1
            return calls <= 6 ? 0 : 1
        }
        try await Self.addUser(server, "owner")
        calls = 0 // アバターの色で使った乱数を数えなおす
        server.inviteCodes["AAAAAA"] = InviteCodeEntry(roomId: "other", createdAt: Self.now)
        let response = try await server.createRoom(Self.simpleRoom())
        #expect(response.inviteCode == "BBBBBB")

        let stuck = Self.makeServer { _ in 0 }
        try await Self.addUser(stuck, "owner")
        stuck.inviteCodes["AAAAAA"] = InviteCodeEntry(roomId: "other", createdAt: Self.now)
        await #expect(throws: InMemoryServer.error(.inviteCodeUnavailable)) {
            try await stuck.createRoom(Self.simpleRoom())
        }
    }

    // MARK: joinRoom

    @Test
    func joinRoomAddsMemberAndAcceptsLooseCode() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        try await Self.addUser(server, "guest")
        let loose = InviteCode.formatted(room.inviteCode).lowercased()
        let joined = try await Self.join(server, "guest", code: loose)
        #expect(joined == JoinRoomResponse(roomId: room.roomId, alreadyMember: false))
        let record = try #require(server.rooms[room.roomId])
        #expect(record.room.memberIds == ["owner", "guest"])
        #expect(record.room.memberCount == 2)
        #expect(record.members["guest"]?.role == .member)
        #expect(record.members["guest"]?.ready == false)

        // もう一度参加しても何も変えず、alreadyMember を返す
        #expect(try await Self.join(server, "guest", code: room.inviteCode).alreadyMember)
        #expect(server.rooms[room.roomId]?.room.memberCount == 2)
    }

    @Test(arguments: ["ZZZZZZ", "123", "OOOOOO"])
    func joinRoomRejectsUnknownCode(code: String) async throws {
        let server = Self.makeServer()
        _ = try await Self.makeRoom(server)
        try await Self.addUser(server, "guest")
        await #expect(throws: InMemoryServer.error(.inviteCodeNotFound)) {
            try await Self.join(server, "guest", code: code)
        }
    }

    /// F-04 の AC「20人のルームに参加しようとすると『このルームは満員です（最大20人）』」（21 人目）
    @Test
    func joinRoomRejectsTwentyFirstMember() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        for index in 2...20 {
            try await Self.addUser(server, "u\(index)")
            _ = try await Self.join(server, "u\(index)", code: room.inviteCode)
        }
        #expect(server.rooms[room.roomId]?.room.memberCount == 20)
        try await Self.addUser(server, "u21")
        let error = await #expect(throws: AppError.self) {
            try await Self.join(server, "u21", code: room.inviteCode)
        }
        #expect(error?.message == "このルームは満員です（最大20人）")
    }

    @Test(arguments: [RoomStatus.drawn, .closed])
    func joinRoomRejectsDecidedRoom(status: RoomStatus) async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        server.rooms[room.roomId]?.room.status = status
        try await Self.addUser(server, "guest")
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            try await Self.join(server, "guest", code: room.inviteCode)
        }
    }

    @Test
    func joinRoomSetsFirstAdFreeSponsor() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        try await Self.addUser(server, "buyer", adFree: true)
        try await Self.addUser(server, "buyer2", adFree: true)
        _ = try await Self.join(server, "buyer", code: room.inviteCode)
        _ = try await Self.join(server, "buyer2", code: room.inviteCode)
        #expect(server.rooms[room.roomId]?.room.adFreeSponsor == AdFreeSponsor(uid: "buyer", displayName: "buyer"))

        // 購入者が抜けたら、残りのメンバーから参加の早い順に探し直す
        try await server.device(of: "buyer").leaveRoom(RoomRequest(roomId: room.roomId))
        #expect(server.rooms[room.roomId]?.room.adFreeSponsor?.uid == "buyer2")
    }

    /// 購入者を探し直すとき、参加の日時が同じなら uid の順（backend の `orderBy("joinedAt")` と同じ）
    @Test
    func adFreeSponsorTieBreaksByUserID() async throws {
        // 時計を止めているので、全員の joinedAt が同じになる
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        // 参加の順（memberIds の順）と uid の順を逆にする
        for userID in ["buyer", "zed", "amy"] {
            try await Self.addUser(server, userID, adFree: true)
            _ = try await Self.join(server, userID, code: room.inviteCode)
        }
        #expect(server.rooms[room.roomId]?.room.adFreeSponsor?.uid == "buyer")
        try await server.device(of: "buyer").leaveRoom(RoomRequest(roomId: room.roomId))
        #expect(server.rooms[room.roomId]?.room.adFreeSponsor?.uid == "amy")
    }

    // MARK: leaveRoom・removeMember

    /// 退出すると、その人のいいね・引き直しの投票・準備OKの数を取り除き、候補は残す（F-05）
    @Test
    func leaveRoomRemovesLikesVotesAndReady() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        try await Self.addUser(server, "guest")
        _ = try await Self.join(server, "guest", code: room.inviteCode)
        server.rooms[room.roomId]?.members["guest"]?.ready = true
        server.rooms[room.roomId]?.members["owner"]?.ready = true
        server.rooms[room.roomId]?.room.readyCount = 2
        server.rooms[room.roomId]?.room.reroll.votesFor = ["owner", "guest"]
        server.rooms[room.roomId]?.candidates["c1"] = Self.candidate(postedBy: "guest", likedBy: ["owner"])
        server.rooms[room.roomId]?.candidates["c2"] = Self.candidate(postedBy: "owner", likedBy: ["guest"])

        try await server.device(of: "guest").leaveRoom(RoomRequest(roomId: room.roomId))
        let record = try #require(server.rooms[room.roomId])
        #expect(record.members["guest"] == nil)
        #expect(record.room.memberIds == ["owner"])
        #expect(record.room.memberCount == 1)
        // onMemberWrite に当たる数え直しで、残った人の準備OKだけを数える
        #expect(record.room.readyCount == 1)
        #expect(record.room.reroll.votesFor == ["owner"])
        #expect(record.candidates["c1"]?.likedBy == ["owner"])
        #expect(record.candidates["c2"]?.likedBy.isEmpty == true)

        // もうメンバーではない
        await #expect(throws: InMemoryServer.error(.notRoomMember)) {
            try await server.device(of: "guest").leaveRoom(RoomRequest(roomId: room.roomId))
        }
    }

    /// F-05「作成者は退出できない」
    @Test
    func ownerCannotLeave() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        await #expect(throws: InMemoryServer.error(.ownerCannotLeave)) {
            try await server.leaveRoom(RoomRequest(roomId: room.roomId))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.leaveRoom(RoomRequest(roomId: "missing"))
        }
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await server.leaveRoom(RoomRequest(roomId: "rooms/other"))
        }
    }

    @Test
    func removeMemberChecksOwnership() async throws {
        let server = Self.makeServer()
        let room = try await Self.makeRoom(server)
        for userID in ["a", "b"] {
            try await Self.addUser(server, userID)
            _ = try await Self.join(server, userID, code: room.inviteCode)
        }
        await #expect(throws: InMemoryServer.error(.notRoomOwner)) {
            try await server.device(of: "a").removeMember(RemoveMemberRequest(roomId: room.roomId, memberId: "b"))
        }
        await #expect(throws: InMemoryServer.error(.cannotRemoveOwner)) {
            try await server.removeMember(RemoveMemberRequest(roomId: room.roomId, memberId: "owner"))
        }
        try await server.removeMember(RemoveMemberRequest(roomId: room.roomId, memberId: "b"))
        #expect(server.rooms[room.roomId]?.room.memberIds == ["owner", "a"])
        await #expect(throws: InMemoryServer.error(.memberNotFound)) {
            try await server.removeMember(RemoveMemberRequest(roomId: room.roomId, memberId: "b"))
        }
    }

    @Test
    func laterCallablesAreNotImplementedYet() async {
        await #expect(throws: AppError(.notImplemented)) {
            try await Self.makeServer().closeRoom(RoomRequest(roomId: "r1"))
        }
    }
}

// MARK: - テストの道具

extension InMemoryServerTests {
    /// ID を順に振る擬似のサーバー。`signedInUserID` は "owner"
    static func makeServer(randomIndex: @escaping (Int) -> Int = { _ in 0 }) -> InMemoryServer {
        var counter = 0
        return InMemoryServer(
            clock: { now },
            randomIndex: randomIndex,
            makeID: {
                counter += 1
                return "id-\(counter)"
            },
            signedInUserID: "owner"
        )
    }

    /// 表示名を登録したユーザーを作る
    static func addUser(_ server: InMemoryServer, _ userID: String, adFree: Bool = false) async throws {
        _ = try await server.device(of: userID).saveProfile(SaveProfileRequest(displayName: userID))
        server.users[userID]?.adFree = adFree
    }

    /// 作成者 "owner" のルームを作る
    static func makeRoom(_ server: InMemoryServer) async throws -> CreateRoomResponse {
        try await addUser(server, "owner")
        return try await server.createRoom(simpleRoom(name: "年末の旅行"))
    }

    /// 全員OK・投稿数 3・共感ブーストのルームの入力
    static func simpleRoom(name: String = "a") -> CreateRoomRequest {
        CreateRoomRequest(name: name, postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost)
    }

    static func join(_ server: InMemoryServer, _ userID: String, code: String) async throws -> JoinRoomResponse {
        try await server.device(of: userID).joinRoom(JoinRoomRequest(inviteCode: code))
    }

    static func candidate(postedBy: String, likedBy: [String]) -> Candidate {
        Candidate(
            place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.29, longitude: 139.48, mapItemId: nil),
            category: .sea,
            note: "",
            url: nil,
            postedBy: postedBy,
            postedByName: postedBy,
            colorIndex: 0,
            likedBy: likedBy,
            fromPastIdeaId: nil,
            createdAt: now
        )
    }
}
