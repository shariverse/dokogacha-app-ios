//
//  FirestorePastIdeasTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import FirebaseFirestore
import Foundation
import Testing

/// 過去のアイデア（`users/{uid}/pastIdeas`。F-13）の Firestore の購読と読み方を、擬似の SDK の窓口で確かめる
struct FirestorePastIdeasTests {
    typealias Base = FirestoreRoomRepositoryTests

    static let closedAt = Date(timeIntervalSince1970: 1_790_000_000)

    /// 過去のアイデアのドキュメント（backend の `PastIdeaDoc` と同じ形）
    static func ideaData(category: String = "sea") -> [String: Any] {
        [
            "sourceRoomId": "r1", "sourceRoomName": "夏の日帰り", "sourceClosedAt": Timestamp(date: closedAt),
            "sourceWinnerName": "城ヶ島",
            "place": ["name": "江の島", "area": "神奈川・藤沢市", "latitude": 35.3, "longitude": 139.48, "mapItemId": NSNull()],
            "category": category, "prevLikeCount": 3
        ]
    }

    /// 自分の過去のアイデアを、元のルームが終了した新しい順に購読し、`Timestamp` を `Date` にして読む
    @Test
    func queriesOwnPastIdeasNewestFirst() async throws {
        let gateway = Base.FakeGateway()
        var iterator = FirestoreRoomRepository(gateway: gateway).pastIdeas(userID: "me").makeAsyncIterator()

        let query = try #require(gateway.queryHandlers.first?.query)
        #expect(query == FirestoreQuerySpec(
            collectionPath: "users/me/pastIdeas",
            order: .init(field: "sourceClosedAt", descending: true)
        ))
        gateway.queryHandlers[0].handler(.success([FirestoreDocument(id: "r1_c2", data: Self.ideaData())]))
        let ideas = try #require(await iterator.next()?.value)
        let expected = PastIdea(
            sourceRoomId: "r1",
            sourceRoomName: "夏の日帰り",
            sourceClosedAt: Self.closedAt,
            sourceWinnerName: "城ヶ島",
            place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: nil),
            category: .sea,
            prevLikeCount: 3
        )
        #expect(ideas == [Identified(id: "r1_c2", value: expected)])
    }

    /// 知らないカテゴリは街歩きにする。読めないドキュメント（場所が無い）は読み飛ばし、ほかは読む
    @Test
    func fallsBackAndSkipsUnreadable() throws {
        let future = try FirestoreDecoding.pastIdea(FirestoreDocument(id: "i1", data: Self.ideaData(category: "zoo-in-the-future")))
        #expect(future.category == .town)
        var broken = Self.ideaData()
        broken["place"] = nil
        let list = FirestoreDecoding.list(
            [FirestoreDocument(id: "bad", data: broken), FirestoreDocument(id: "ok", data: Self.ideaData())],
            FirestoreDecoding.pastIdea
        )
        #expect(list.map(\.id) == ["ok"])
    }
}
