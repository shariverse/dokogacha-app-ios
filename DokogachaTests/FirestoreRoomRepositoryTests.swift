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
        var documentHandlers: [String: (Result<FirestoreDocument?, ServerFailure>) -> Void] = [:]
        var queryHandlers: [(query: FirestoreQuerySpec, handler: (Result<[FirestoreDocument], ServerFailure>) -> Void)] = []
        var tokens: [FakeToken] = []
        var updates: [(path: String, fields: [String: FirestoreFieldUpdate])] = []
        var updateError: ServerFailure?

        func listenDocument(
            path: String,
            handler: @escaping (Result<FirestoreDocument?, ServerFailure>) -> Void
        ) -> any FirestoreListenerToken {
            documentHandlers[path] = handler
            return makeToken()
        }

        func listenQuery(
            _ query: FirestoreQuerySpec,
            handler: @escaping (Result<[FirestoreDocument], ServerFailure>) -> Void
        ) -> any FirestoreListenerToken {
            queryHandlers.append((query, handler))
            return makeToken()
        }

        func update(path: String, fields: [String: FirestoreFieldUpdate]) async throws {
            updates.append((path, fields))
            if let updateError {
                throw updateError
            }
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
        let handler = try #require(gateway.documentHandlers["rooms/r1"])

        handler(.success(FirestoreDocument(id: "r1", data: Self.roomData(status: "archived"))))
        #expect(await iterator.next() == .failure(AppError(.unreadableData)))
        handler(.success(nil))
        #expect(await iterator.next() == .value(nil))
        handler(.success(FirestoreDocument(id: "r1", data: Self.roomData(status: "unlocked"))))
        guard case let .value(room?) = try #require(await iterator.next()) else {
            Issue.record("ルームが流れていない")
            return
        }
        #expect(room.status == .unlocked)
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

    @Test
    func writeFailureBecomesAppError() async {
        let gateway = FakeGateway()
        gateway.updateError = ServerFailure(code: .unavailable)
        await #expect(throws: AppError(.network, code: .unavailable)) {
            try await FirestoreRoomRepository(gateway: gateway).setReady(false, roomID: "r1", userID: "me")
        }
    }
}
