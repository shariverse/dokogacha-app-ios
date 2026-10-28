//
//  PastIdeaListTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の「過去のアイデア」の並び（02 の §3.4 F-13）と「前回惜しかった」の判定を確かめる
struct PastIdeaListTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func idea(_ id: String, room: String, daysAgo: Double, likes: Int, name: String? = nil) -> Identified<PastIdea> {
        Identified(id: id, value: PastIdea(
            sourceRoomId: room,
            sourceRoomName: "ルーム\(room)",
            sourceClosedAt: now.addingTimeInterval(-daysAgo * 86_400),
            sourceWinnerName: "当選\(room)",
            place: Place(name: name ?? id, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: nil),
            category: .town,
            prevLikeCount: likes
        ))
    }

    /// ルームごとにまとめ、新しいルーム順に並べる。見出しはルーム名・終了の日時・当選の場所。中は前回のいいねが多い順（同じなら ID 順）
    @Test
    func groupsByRoomNewestFirst() throws {
        let ideas = [
            Self.idea("old_a", room: "old", daysAgo: 30, likes: 0),
            Self.idea("new_b", room: "new", daysAgo: 3, likes: 1),
            Self.idea("new_a", room: "new", daysAgo: 3, likes: 1),
            Self.idea("new_c", room: "new", daysAgo: 3, likes: 4),
            Self.idea("mid_a", room: "mid", daysAgo: 12, likes: 2)
        ]
        let groups = PastIdeaList.groups(ideas)

        #expect(groups.map(\.id) == ["new", "mid", "old"])
        let first = try #require(groups.first)
        #expect(first.roomName == "ルームnew")
        #expect(first.winnerName == "当選new")
        #expect(first.closedAt == Self.now.addingTimeInterval(-3 * 86_400))
        #expect(first.ideas.map(\.id) == ["new_c", "new_a", "new_b"])
        #expect(PastIdeaList.groups([]).isEmpty)
    }

    /// 同じ日時に終了したルームは、ルームの ID の降順（並びが揺れない）
    @Test
    func tiesAreOrderedByRoomID() {
        let ideas = [Self.idea("a_1", room: "a", daysAgo: 1, likes: 0), Self.idea("b_1", room: "b", daysAgo: 1, likes: 0)]
        #expect(PastIdeaList.groups(ideas).map(\.id) == ["b", "a"])
    }

    /// 前回のいいねが 3 以上なら「前回惜しかった」（02 の §3.4。2 は付けない）
    @Test(arguments: [(0, false), (2, false), (3, true), (5, true)])
    func closeCallFromThreeLikes(_ likes: Int, _ expected: Bool) {
        #expect(PastIdeaList.isCloseCall(Self.idea("i", room: "r", daysAgo: 1, likes: likes).value) == expected)
    }

    /// 持ち込みの S-09 は、過去のアイデアの ID・場所・前回のカテゴリから始める
    @Test
    func draftPlaceKeepsPlaceAndCategory() {
        var idea = Self.idea("r_c2", room: "r", daysAgo: 1, likes: 0, name: "江の島")
        idea.value.category = .sea
        let draft = PastIdeaList.draftPlace(idea)
        #expect(draft.id == "r_c2")
        #expect(draft.place == idea.place)
        #expect(draft.category == .sea)
    }
}
