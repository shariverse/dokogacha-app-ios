//
//  InMemoryServerPastIdeaTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの過去のアイデア（F-13）を確かめる。持ち込み（`addCandidate` の `fromPastIdeaId`）は backend の
/// `candidates/service.ts` の `assertOwnPastIdea` と同じ規則。データと道具は `InMemoryServerCandidateTests` と同じ
struct InMemoryServerPastIdeaTests {
    typealias Base = InMemoryServerCandidateTests

    /// 過去のアイデア（持ち込み元）
    static let pastIdea = PastIdea(
        sourceRoomId: "old",
        sourceRoomName: "夏の日帰り",
        sourceClosedAt: InMemoryServerTests.now,
        sourceWinnerName: "城ヶ島",
        place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: nil),
        category: .sea,
        prevLikeCount: 3
    )

    /// 持ち込み元が自分の過去のアイデアに無ければ（他人の・無い ID）`invalid-argument` で、何も作らない（backend の `assertOwnPastIdea`）
    @Test
    func addRejectsUnknownPastIdea() async throws {
        let server = InMemoryServerTests.makeServer()
        let roomID = try await Base.makeRoom(server)
        server.pastIdeas["carol"] = ["idea1": Self.pastIdea]
        let bob = server.device(of: "bob")
        for ideaID in ["idea1", "missing"] {
            await #expect(throws: InMemoryServer.error(.invalidArgument)) {
                try await bob.addCandidate(Base.request(roomID, fromPastIdeaID: ideaID))
            }
        }
        #expect(server.rooms[roomID]?.candidates.isEmpty == true)
        // 過去のアイデアは持ち込んでも残す
        server.pastIdeas["bob"] = ["idea1": Self.pastIdea]
        _ = try await bob.addCandidate(Base.request(roomID, fromPastIdeaID: "idea1"))
        #expect(server.pastIdeas["bob"]?["idea1"] == Self.pastIdea)
    }

    /// 自分の過去のアイデアを、元のルームが終了した新しい順に流し、増えたら流し直す。他人の過去のアイデアは読めない（ルール）
    @Test
    func subscribesOwnPastIdeasNewestFirst() async throws {
        let server = InMemoryServer.demo(.empty)
        var older = Self.pastIdea
        older.sourceClosedAt = InMemoryServerTests.now.addingTimeInterval(-86_400)
        server.pastIdeas[DemoScenario.myUserID] = ["old_c1": older]
        var ideas = server.pastIdeas(userID: DemoScenario.myUserID).makeAsyncIterator()
        #expect(await ideas.next()?.value?.map(\.id) == ["old_c1"])

        server.pastIdeas[DemoScenario.myUserID]?["new_c1"] = Self.pastIdea
        #expect(await ideas.next()?.value?.map(\.id) == ["new_c1", "old_c1"])

        var others = server.pastIdeas(userID: "demo-haruka").makeAsyncIterator()
        #expect(await others.next() == .failure(InMemoryServer.permissionDenied))
        #expect(await others.next() == nil)
    }

    /// `past-ideas` のデモは、候補のあるデモのルームと、自分の過去のアイデア 2 つのルーム・5 件（起動引数で選べる）
    @Test
    func pastIdeasScenario() {
        #expect(DemoScenario.from(arguments: ["-demo-scenario", "past-ideas"]) == .pastIdeas)
        let server = InMemoryServer.demo(.pastIdeas) { InMemoryServerTests.now }
        #expect(server.rooms[DemoScenario.roomID]?.candidates.count == 3)
        let ideas = server.pastIdeas[DemoScenario.myUserID] ?? [:]
        #expect(ideas.count == 5)
        #expect(Set(ideas.values.map(\.sourceRoomId)) == [DemoScenario.pastSummerRoomID, DemoScenario.pastSeminarRoomID])
        #expect(ideas["\(DemoScenario.pastSummerRoomID)_c2"]?.place.name == "鎌倉大仏")
    }
}
