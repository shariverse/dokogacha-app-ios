//
//  FirestoreRoomRepositoryTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import FirebaseFirestore
import Foundation
import Testing

/// Firestore の購読（`addSnapshotListener` → `AsyncStream`）と直接の書き込みを、擬似の SDK の窓口で確かめる
struct FirestoreRoomRepositoryTests {
    /// 外したかを覚える擬似のリスナーの札
    @MainActor
    final class FakeToken: FirestoreListenerToken {
        private(set) var isRemoved = false

        func remove() {
            isRemoved = true
        }
    }

    /// 登録されたリスナーと書き込みを覚える擬似の SDK の窓口
    final class FakeGateway: FirestoreGateway {
        var documentHandlers: [String: (Result<FirestoreDocumentSnapshot, ServerFailure>) -> Void] = [:]
        /// ドキュメントの購読で、メタデータの変化も受け取るよう頼まれたか（パスごと）
        var includesMetadataChanges: [String: Bool] = [:]
        var queryHandlers: [(query: FirestoreQuerySpec, handler: (Result<[FirestoreDocument], ServerFailure>) -> Void)] = []
        var tokens: [FakeToken] = []
        var updates: [(path: String, fields: [String: FirestoreFieldUpdate])] = []

        func listenDocument(
            path: String,
            includeMetadataChanges: Bool,
            handler: @escaping (Result<FirestoreDocumentSnapshot, ServerFailure>) -> Void
        ) -> any FirestoreListenerToken {
            documentHandlers[path] = handler
            includesMetadataChanges[path] = includeMetadataChanges
            return makeToken()
        }

        func listenQuery(
            _ query: FirestoreQuerySpec,
            handler: @escaping (Result<[FirestoreDocument], ServerFailure>) -> Void
        ) -> any FirestoreListenerToken {
            queryHandlers.append((query, handler))
            return makeToken()
        }

        /// 送ったものを覚えるだけ（本物の SDK と同じく、サーバーの完了は待たない）
        func update(path: String, fields: [String: FirestoreFieldUpdate]) {
            updates.append((path, fields))
        }

        /// ドキュメントの購読にスナップショットを渡す（`isFromCache` が false ならサーバーの値）
        func sendDocument(_ document: FirestoreDocument?, path: String, isFromCache: Bool = false) {
            documentHandlers[path]?(.success(FirestoreDocumentSnapshot(document: document, isFromCache: isFromCache)))
        }

        private func makeToken() -> FakeToken {
            let token = FakeToken()
            tokens.append(token)
            return token
        }
    }

    static let createdAt = Date(timeIntervalSince1970: 1_790_000_000.123)

    /// backend が書く形のルーム（日時は `Timestamp`、無い値は `NSNull`）
    static func roomData(status: String = "open") -> [String: Any] {
        [
            "name": "年末の旅行", "ownerId": "owner", "inviteCode": "DK729Q", "status": status,
            "settings": ["postLimit": 3, "unlockRule": "all", "deadlineAt": NSNull(), "likeMode": "boost"],
            "forcedUnlock": false, "memberIds": ["owner"], "memberCount": 1, "readyCount": 0, "candidateCount": 0,
            "adFreeSponsor": NSNull(), "currentDrawId": NSNull(), "winnerCandidateId": NSNull(), "excludedCandidateIds": [String](),
            "reroll": [
                "used": false, "proposedBy": NSNull(), "proposedAt": NSNull(),
                "votesFor": [String](), "votesAgainst": [String](), "status": "none"
            ],
            "createdAt": Timestamp(date: createdAt), "drawnAt": NSNull(), "closedAt": NSNull()
        ]
    }

    static func memberData(role: String) -> [String: Any] {
        [
            "displayName": "はるか", "avatarColor": "#B8321A", "role": role, "ready": true,
            "joinedAt": Timestamp(date: createdAt), "lastSeenAt": Timestamp(date: createdAt.addingTimeInterval(60))
        ]
    }

    static func candidateData(category: String) -> [String: Any] {
        [
            "place": ["name": "江の島", "area": "神奈川・藤沢市", "latitude": 35.29, "longitude": 139.48],
            "category": category, "note": "", "postedBy": "owner", "postedByName": "たくみ", "colorIndex": 0,
            "likedBy": ["a", "b"], "createdAt": Timestamp(date: createdAt)
        ]
    }

    @Test
    func activeRoomsQueriesMyActiveRoomsNewestFirst() async throws {
        let gateway = FakeGateway()
        let repository = FirestoreRoomRepository(gateway: gateway)
        var iterator = repository.activeRooms(userID: "me").makeAsyncIterator()

        let query = try #require(gateway.queryHandlers.first?.query)
        #expect(query.collectionPath == "rooms")
        let filters: [FirestoreQuerySpec.Filter] = [
            .arrayContains(field: "memberIds", value: "me"),
            .isIn(field: "status", values: ["open", "unlocked", "drawn"])
        ]
        #expect(query.filters == filters)
        #expect(query.order == .init(field: "createdAt", descending: true))

        gateway.queryHandlers[0].handler(.success([FirestoreDocument(id: "r1", data: Self.roomData())]))
        let rooms = try #require(await iterator.next()?.value)
        #expect(rooms.map(\.id) == ["r1"])
        #expect(rooms[0].status == .open)
        #expect(rooms[0].settings.deadlineAt == nil)
    }

    /// `Timestamp` を `Date` にする（ミリ秒まで落とさない）
    @Test
    func convertsTimestampToDate() throws {
        let room = try FirestoreDecoding.room(FirestoreDocument(id: "r1", data: Self.roomData()))
        #expect(room.createdAt == Self.createdAt)
        let member = try FirestoreDecoding.member(FirestoreDocument(id: "u1", data: Self.memberData(role: "member")))
        #expect(member.lastSeenAt == Self.createdAt.addingTimeInterval(60))
    }

    /// 知らないカテゴリは街歩き、知らない役割は member に落とす
    @Test
    func fallsBackForUnknownCategoryAndRole() throws {
        let future = FirestoreDocument(id: "c1", data: Self.candidateData(category: "zoo-in-the-future"))
        let candidate = try FirestoreDecoding.candidate(future)
        #expect(candidate.category == .town)
        #expect(candidate.likedBy == ["a", "b"])
        let member = try FirestoreDecoding.member(FirestoreDocument(id: "u1", data: Self.memberData(role: "moderator")))
        #expect(member.role == .member)
    }

    /// 知らない状態のルームは一覧から読み飛ばし、ほかのルームは読める
    @Test
    func skipsUnreadableDocumentsInList() async throws {
        let gateway = FakeGateway()
        var iterator = FirestoreRoomRepository(gateway: gateway).activeRooms(userID: "me").makeAsyncIterator()
        gateway.queryHandlers[0].handler(.success([
            FirestoreDocument(id: "new", data: Self.roomData(status: "archived")),
            FirestoreDocument(id: "ok", data: Self.roomData())
        ]))
        let rooms = try #require(await iterator.next()?.value)
        #expect(rooms.map(\.id) == ["ok"])
    }

    /// 1 つのルームの購読: 読めないときは unreadableData を流して続け、無いときは nil
    @Test
    func roomStreamReportsUnreadableAndMissing() async throws {
        let gateway = FakeGateway()
        var iterator = FirestoreRoomRepository(gateway: gateway).room(id: "r1").makeAsyncIterator()
        #expect(gateway.documentHandlers["rooms/r1"] != nil)
        // ルームはキャッシュの「無い」もそのまま流す（メタデータだけの変化は要らない）
        #expect(gateway.includesMetadataChanges["rooms/r1"] == false)

        gateway.sendDocument(FirestoreDocument(id: "r1", data: Self.roomData(status: "archived")), path: "rooms/r1")
        #expect(await iterator.next() == .failure(AppError(.unreadableData)))
        gateway.sendDocument(nil, path: "rooms/r1", isFromCache: true)
        #expect(await iterator.next() == .value(nil))
        gateway.sendDocument(FirestoreDocument(id: "r1", data: Self.roomData(status: "unlocked")), path: "rooms/r1")
        guard case let .value(room?) = try #require(await iterator.next()) else {
            Issue.record("ルームが流れていない")
            return
        }
        #expect(room.status == .unlocked)
    }

    /// 抽選の記録は `rooms/{roomId}/draws/{drawId}` を購読し、backend が書く形（日時は `Timestamp`・重みは map）を読む
    @Test
    func drawStreamReadsRecord() async throws {
        let gateway = FakeGateway()
        var iterator = FirestoreRoomRepository(gateway: gateway).draw(roomID: "r1", drawID: "d1").makeAsyncIterator()
        let path = "rooms/r1/draws/d1"
        #expect(gateway.documentHandlers[path] != nil)
        let data: [String: Any] = [
            "candidateId": "c1", "probability": 0.5, "weights": ["c1": 2.0, "c2": 2.0], "drawnBy": "u1",
            "drawnByName": "はるか", "isReroll": false, "createdAt": Timestamp(date: Self.createdAt)
        ]
        gateway.sendDocument(FirestoreDocument(id: "d1", data: data), path: path)
        #expect(await iterator.next() == .value(Draw(
            candidateId: "c1",
            probability: 0.5,
            weights: ["c1": 2, "c2": 2],
            drawnBy: "u1",
            drawnByName: "はるか",
            isReroll: false,
            createdAt: Self.createdAt
        )))
        gateway.sendDocument(nil, path: path)
        #expect(await iterator.next() == .value(nil))
    }

    /// 思い出のきっぷの終了したルームは、自分が入っている `closed` を終了の新しい順に、上限の数だけ読む（上限なしも選べる）
    @Test
    func closedRoomsQueriesWithLimit() {
        let gateway = FakeGateway()
        let repository = FirestoreRoomRepository(gateway: gateway)
        _ = repository.closedRooms(userID: "me", limit: 6)
        _ = repository.closedRooms(userID: "me", limit: nil)
        let limited = FirestoreQuerySpec(
            collectionPath: "rooms",
            filters: [.arrayContains(field: "memberIds", value: "me"), .isIn(field: "status", values: ["closed"])],
            order: .init(field: "closedAt", descending: true),
            limit: 6
        )
        var unlimited = limited
        unlimited.limit = nil
        #expect(gateway.queryHandlers.map(\.query) == [limited, unlimited])
    }

    /// リスナーが失敗したら（メンバーから外されて読めなくなったなど）、失敗を流して終わる
    @Test
    func listenerFailureFinishesStream() async throws {
        let gateway = FakeGateway()
        var iterator = FirestoreRoomRepository(gateway: gateway).members(roomID: "r1").makeAsyncIterator()
        let expected = FirestoreQuerySpec(collectionPath: "rooms/r1/members", order: .init(field: "joinedAt", descending: false))
        #expect(gateway.queryHandlers[0].query == expected)
        gateway.queryHandlers[0].handler(.failure(ServerFailure(code: .permissionDenied)))
        #expect(await iterator.next() == .failure(AppError(.permissionDenied, code: .permissionDenied)))
        #expect(await iterator.next() == nil)
    }

    /// 購読している Task を cancel すると、リスナーを外す
    @Test
    func cancellingRemovesListener() async throws {
        let gateway = FakeGateway()
        let stream = FirestoreRoomRepository(gateway: gateway).candidates(roomID: "r1")
        #expect(gateway.queryHandlers[0].query.order == .init(field: "createdAt", descending: true))
        let token = try #require(gateway.tokens.first)
        let task = Task {
            for await _ in stream {}
        }
        #expect(!token.isRemoved)
        task.cancel()
        await task.value
        #expect(await AsyncTestSupport.eventually { token.isRemoved })
    }

    @Test
    func writesOnlyAllowedFields() async throws {
        let gateway = FakeGateway()
        let repository = FirestoreRoomRepository(gateway: gateway)
        try await repository.setReady(true, roomID: "r1", userID: "me")
        try await repository.setLike(true, candidateID: "c1", roomID: "r1", userID: "me")
        try await repository.setLike(false, candidateID: "c1", roomID: "r1", userID: "me")
        try await repository.markSeen(roomID: "r1", userID: "me")

        let member = "rooms/r1/members/me"
        let candidate = "rooms/r1/candidates/c1"
        #expect(gateway.updates.map(\.path) == [member, candidate, candidate, member])
        #expect(gateway.updates.map(\.fields) == [
            ["ready": .bool(true)],
            ["likedBy": .arrayUnion(["me"])],
            ["likedBy": .arrayRemove(["me"])],
            ["lastSeenAt": .serverTimestamp]
        ])
    }
}
