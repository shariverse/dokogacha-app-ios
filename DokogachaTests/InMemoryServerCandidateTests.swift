//
//  InMemoryServerCandidateTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `addCandidate`・`deleteCandidate`・いいねが、backend と同じ検証・状態遷移をすることを確かめる
/// （backend の `test/emulator/candidates-service.test.ts`・`firestore-rules.test.ts` の candidates と同じ観点）
struct InMemoryServerCandidateTests {
    /// 江の島
    nonisolated static let enoshima = Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48)

    /// 作成者 "owner"・メンバー "bob"・"carol" のルーム（投稿数の上限は `postLimit`）
    static func makeRoom(_ server: InMemoryServer, postLimit: Int = 3) async throws -> String {
        try await InMemoryServerTests.addUser(server, "owner")
        let room = try await server.createRoom(
            CreateRoomRequest(name: "年末の旅行", postLimit: postLimit, unlockRule: .all, deadline: nil, likeMode: .boost)
        )
        for userID in ["bob", "carol"] {
            try await InMemoryServerTests.addUser(server, userID)
            _ = try await InMemoryServerTests.join(server, userID, code: room.inviteCode)
        }
        return room.roomId
    }

    /// `place` を追加する入力
    static func request(
        _ roomID: String,
        place: Place = enoshima,
        note: String = "海！",
        url: String? = nil,
        fromPastIdeaID: String? = nil
    ) -> AddCandidateRequest {
        AddCandidateRequest(roomId: roomID, place: place, category: .sea, note: note, url: url, fromPastIdeaId: fromPastIdeaID)
    }

    /// 名前の違う場所（重複しない）
    static func place(named name: String) -> Place {
        Place(name: name, area: enoshima.area, latitude: enoshima.latitude, longitude: enoshima.longitude)
    }

    /// `userID` の端末から候補を追加し、ID を返す（重複になったら失敗する）
    static func add(_ server: InMemoryServer, _ userID: String, _ roomID: String, place: Place = enoshima) async throws -> String {
        let result = try await server.device(of: userID).addCandidate(request(roomID, place: place))
        guard case let .added(candidateID) = result else {
            Issue.record("重複になった: \(result)")
            return ""
        }
        return candidateID
    }

    // MARK: addCandidate（F-10）

    /// 候補を作り、ルームの候補数を増やす（いいねは 0・投稿者名はルームの表示名・投稿日時はサーバーの時刻・前後の空白を取り除く）
    @Test
    func addCreatesCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let place = Place(name: " 江の島 ", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: "I1")
        server.pastIdeas["bob"] = ["idea1": InMemoryServerPastIdeaTests.pastIdea]
        let result = try await server.device(of: "bob").addCandidate(
            Self.request(roomID, place: place, note: " 海！ ", url: " https://example.com ", fromPastIdeaID: "idea1")
        )
        guard case let .added(candidateID) = result else {
            Issue.record("追加されなかった: \(result)")
            return
        }
        let record = try #require(server.rooms[roomID])
        #expect(record.candidates[candidateID] == Candidate(
            place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: "I1"),
            category: .sea,
            note: "海！",
            url: "https://example.com",
            postedBy: "bob",
            postedByName: "bob",
            colorIndex: 0,
            likedBy: [],
            fromPastIdeaId: "idea1",
            createdAt: InMemoryServerTests.now
        ))
        #expect(record.room.candidateCount == 1)
    }

    /// `colorIndex` は投稿順の通し番号（消しても残りの番号は詰めない）
    @Test
    func colorIndexKeepsIncreasingAfterDelete() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let first = try await Self.add(server, "bob", roomID, place: Self.place(named: "a"))
        _ = try await Self.add(server, "carol", roomID, place: Self.place(named: "b"))
        _ = try await Self.add(server, "owner", roomID, place: Self.place(named: "c"))
        try await server.device(of: "bob").deleteCandidate(CandidateRequest(roomId: roomID, candidateId: first))
        let fourth = try await Self.add(server, "bob", roomID, place: Self.place(named: "d"))
        #expect(server.rooms[roomID]?.candidates[fourth]?.colorIndex == 3)
        #expect(server.rooms[roomID]?.room.candidateCount == 3)
    }

    /// 同じ場所（場所名が同じで 100m 以内・識別子が同じ）は作らずに既存の候補を返す（自分の投稿でも）
    @Test
    func duplicateReturnsExistingCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let withID = Place(name: "江の島", area: "", latitude: 35.3, longitude: 139.48, mapItemId: "I1")
        let existing = try await Self.add(server, "bob", roomID, place: withID)
        let carol = server.device(of: "carol")
        let nearby = Place(name: "江の島", area: "", latitude: 35.3005, longitude: 139.48)
        #expect(try await carol.addCandidate(Self.request(roomID, place: nearby)) == .duplicate(of: existing))
        let sameID = Place(name: "江ノ島", area: "", latitude: 35.4, longitude: 139.48, mapItemId: "I1")
        #expect(try await carol.addCandidate(Self.request(roomID, place: sameID)) == .duplicate(of: existing))
        #expect(try await server.device(of: "bob").addCandidate(Self.request(roomID)) == .duplicate(of: existing))
        #expect(server.rooms[roomID]?.candidates.keys.sorted() == [existing])
        #expect(server.rooms[roomID]?.room.candidateCount == 1)
    }

    /// 場所名が同じでも 100m を超えれば別の候補
    @Test
    func sameNameFarAwayIsAdded() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        _ = try await Self.add(server, "bob", roomID)
        _ = try await Self.add(server, "carol", roomID, place: Place(name: "江の島", area: "", latitude: 35.301, longitude: 139.48))
        #expect(server.rooms[roomID]?.room.candidateCount == 2)
    }

    /// 自分の投稿数がルームの上限に達したら「上限」（同じ場所なら重複を先に返す。ほかの人は投稿できる）
    @Test
    func postLimitPerMember() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server, postLimit: 2)
        let first = try await Self.add(server, "bob", roomID, place: Self.place(named: "a"))
        _ = try await Self.add(server, "bob", roomID, place: Self.place(named: "b"))
        let bob = server.device(of: "bob")
        await #expect(throws: InMemoryServer.error(.postLimitReached)) {
            try await bob.addCandidate(Self.request(roomID, place: Self.place(named: "c")))
        }
        #expect(try await bob.addCandidate(Self.request(roomID, place: Self.place(named: "a"))) == .duplicate(of: first))
        _ = try await Self.add(server, "carol", roomID, place: Self.place(named: "c"))
        #expect(server.rooms[roomID]?.room.candidateCount == 3)
    }

    /// ルームの候補が 200 件なら追加できない（退出した人の候補が残ったとき）
    @Test
    func roomCandidatesLimit() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server, postLimit: 10)
        for index in 0..<DomainConstants.Limits.maxCandidates {
            var candidate = InMemoryServerTests.candidate(postedBy: "left\(index)", likedBy: [])
            candidate.place = Self.place(named: "場所\(index)")
            server.rooms[roomID]?.candidates["seed\(index)"] = candidate
        }
        await #expect(throws: InMemoryServer.error(.roomCandidatesFull)) {
            try await server.device(of: "bob").addCandidate(Self.request(roomID))
        }
    }

    /// drawn・closed では追加できない（「このルームはもう行き先が決まっています」）
    @Test(arguments: [RoomStatus.drawn, .closed])
    func cannotAddAfterDraw(status: RoomStatus) async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        server.rooms[roomID]?.room.status = status
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            try await server.device(of: "bob").addCandidate(Self.request(roomID))
        }
    }

    /// メンバーでなければ追加できない・ルームが無ければ「ルームが見つかりません」
    @Test
    func addRequiresMembership() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        try await InMemoryServerTests.addUser(server, "dave")
        await #expect(throws: InMemoryServer.error(.notRoomMember)) {
            try await server.device(of: "dave").addCandidate(Self.request(roomID))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.device(of: "bob").addCandidate(Self.request("missing"))
        }
        #expect(server.rooms[roomID]?.room.candidateCount == 0)
    }

    /// 正しくない入力（ルームの ID が "r" のものは、テストで作ったルームの ID に差し替える）
    nonisolated static func invalid(
        roomID: String = "r",
        place: Place = enoshima,
        note: String = "",
        url: String? = nil,
        fromPastIdeaID: String? = nil
    ) -> AddCandidateRequest {
        AddCandidateRequest(roomId: roomID, place: place, category: .sea, note: note, url: url, fromPastIdeaId: fromPastIdeaID)
    }

    nonisolated static let invalidRequests: [AddCandidateRequest] = [
        invalid(note: String(repeating: "あ", count: 41)),
        invalid(note: "海\nいきたい"),
        invalid(place: Place(name: "江の島", area: "", latitude: 91, longitude: 0)),
        invalid(place: Place(name: " ", area: "", latitude: 0, longitude: 0)),
        invalid(url: "javascript:alert(1)"),
        invalid(fromPastIdeaID: ".."),
        invalid(roomID: "a/b")
    ]

    /// 入力が正しくなければ「入力内容を確認してください」（何も作らない）
    @Test(arguments: invalidRequests)
    func rejectsInvalidInput(request: AddCandidateRequest) async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        var request = request
        if request.roomId == "r" {
            request.roomId = roomID
        }
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await server.device(of: "bob").addCandidate(request)
        }
        #expect(server.rooms[roomID]?.candidates.isEmpty == true)
    }

    /// 空白だけの参考 URL は保存しない
    @Test
    func blankURLIsNotSaved() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let result = try await server.addCandidate(Self.request(roomID, url: "  "))
        guard case let .added(candidateID) = result else {
            Issue.record("追加されなかった: \(result)")
            return
        }
        #expect(server.rooms[roomID]?.candidates[candidateID]?.url == nil)
    }

    // MARK: deleteCandidate（F-11）

    /// 投稿した人は自分の候補を削除できる（いいねも一緒に消え、候補数が減る）
    @Test
    func posterDeletesOwnCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        await server.device(of: "carol").setLike(true, candidateID: candidateID, roomID: roomID)
        #expect(server.rooms[roomID]?.candidates[candidateID]?.likedBy == ["carol"])
        try await server.device(of: "bob").deleteCandidate(CandidateRequest(roomId: roomID, candidateId: candidateID))
        #expect(server.rooms[roomID]?.candidates.isEmpty == true)
        #expect(server.rooms[roomID]?.room.candidateCount == 0)
    }

    /// 作成者は誰の候補でも削除できる
    @Test
    func ownerDeletesAnyCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        try await server.deleteCandidate(CandidateRequest(roomId: roomID, candidateId: candidateID))
        #expect(server.rooms[roomID]?.candidates.isEmpty == true)
    }

    /// 投稿した人でも作成者でもなければ削除できない
    @Test
    func otherMemberCannotDelete() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        await #expect(throws: InMemoryServer.error(.notCandidateOwner)) {
            try await server.device(of: "carol").deleteCandidate(CandidateRequest(roomId: roomID, candidateId: candidateID))
        }
        #expect(server.rooms[roomID]?.candidates[candidateID] != nil)
    }

    /// drawn・closed では投稿した人も作成者も削除できない
    @Test(arguments: [RoomStatus.drawn, .closed])
    func cannotDeleteAfterDraw(status: RoomStatus) async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        server.rooms[roomID]?.room.status = status
        for userID in ["bob", "owner"] {
            await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
                try await server.device(of: userID).deleteCandidate(CandidateRequest(roomId: roomID, candidateId: candidateID))
            }
        }
        #expect(server.rooms[roomID]?.room.candidateCount == 1)
    }

    /// ガチャで当選した候補（今の当選・引き直しで除外した前の当選・抽選の記録が指す候補）は、unlocked でも消せない（backend と同じ）
    @Test
    func cannotDeleteDrawnCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server, postLimit: 5)
        let winner = try await Self.add(server, "bob", roomID)
        let excluded = try await Self.add(server, "bob", roomID, place: Self.place(named: "鎌倉"))
        let recorded = try await Self.add(server, "bob", roomID, place: Self.place(named: "葉山"))
        let free = try await Self.add(server, "bob", roomID, place: Self.place(named: "逗子"))
        server.rooms[roomID]?.room.status = .unlocked
        server.rooms[roomID]?.room.winnerCandidateId = winner
        server.rooms[roomID]?.room.excludedCandidateIds = [excluded]
        server.rooms[roomID]?.draws["d0"] = Draw(
            candidateId: recorded,
            probability: 0.5,
            weights: [:],
            drawnBy: "owner",
            drawnByName: "owner",
            isReroll: false,
            createdAt: InMemoryServerTests.now
        )
        for candidateID in [winner, excluded, recorded] {
            for userID in ["bob", "owner"] {
                await #expect(throws: InMemoryServer.error(.candidateDrawn)) {
                    try await server.device(of: userID).deleteCandidate(CandidateRequest(roomId: roomID, candidateId: candidateID))
                }
            }
        }
        try await server.device(of: "bob").deleteCandidate(CandidateRequest(roomId: roomID, candidateId: free))
        #expect(server.rooms[roomID]?.room.candidateCount == 3)
    }

    /// 候補が無ければ「候補が見つかりません」・メンバーでなければ削除できない
    @Test
    func deleteMissingCandidateOrNonMember() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        let request = CandidateRequest(roomId: roomID, candidateId: candidateID)
        try await server.device(of: "bob").deleteCandidate(request)
        await #expect(throws: InMemoryServer.error(.candidateNotFound)) {
            try await server.device(of: "bob").deleteCandidate(request)
        }
        await #expect(throws: InMemoryServer.error(.notRoomMember)) {
            try await server.device(of: "dave").deleteCandidate(request)
        }
    }

    // MARK: いいね（F-20。ルールと同じ）

    /// 追加した候補に、投稿した人以外がいいねできる。投稿した人のいいねは拒まれる（自分の投稿にはいいねできない）
    @Test
    func likesOnAddedCandidate() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Self.makeRoom(server)
        let candidateID = try await Self.add(server, "bob", roomID)
        try await server.setLike(true, candidateID: candidateID, roomID: roomID, userID: "owner")
        await server.device(of: "bob").setLike(true, candidateID: candidateID, roomID: roomID)
        #expect(server.rooms[roomID]?.candidates[candidateID]?.likedBy == ["owner"])
        #expect(server.rejectedWrites == [InMemoryServer.permissionDenied])
    }
}
