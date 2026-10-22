//
//  CandidateListTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 候補一覧の並び順と NEW の判定（F-12）を確かめる。
struct CandidateListTests {
    /// 自分の uid
    nonisolated static let myUID = "me"

    /// 基準の時刻
    nonisolated static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// 候補を作る
    static func candidate(postedBy: String = "other", createdAt: Date) -> Candidate {
        Candidate(
            place: Place(name: "すみだ水族館", area: "東京・墨田区", latitude: 35.71, longitude: 139.81, mapItemId: nil),
            category: .aquarium,
            note: "",
            url: nil,
            postedBy: postedBy,
            postedByName: "みさき",
            colorIndex: 0,
            likedBy: [],
            fromPastIdeaId: nil,
            createdAt: createdAt
        )
    }

    /// 新しい順に並び、同じ時刻は ID の昇順
    @Test
    func sortedNewestFirst() {
        let candidates = [
            Identified(id: "a", value: Self.candidate(createdAt: Self.base)),
            Identified(id: "c", value: Self.candidate(createdAt: Self.base.addingTimeInterval(60))),
            Identified(id: "d", value: Self.candidate(createdAt: Self.base.addingTimeInterval(120))),
            Identified(id: "b", value: Self.candidate(createdAt: Self.base.addingTimeInterval(60)))
        ]
        #expect(CandidateList.sorted(candidates).map(\.id) == ["d", "b", "c", "a"])
    }

    /// lastSeenAt より後の他人の投稿だけが NEW（同じ時刻・前・自分の投稿は NEW にしない）
    @Test
    func newBadge() {
        func isNew(_ candidate: Candidate) -> Bool {
            CandidateList.isNew(candidate, myUID: Self.myUID, lastSeenAt: Self.base)
        }
        #expect(isNew(Self.candidate(createdAt: Self.base.addingTimeInterval(1))))
        #expect(!isNew(Self.candidate(createdAt: Self.base)))
        #expect(!isNew(Self.candidate(createdAt: Self.base.addingTimeInterval(-1))))
        #expect(!isNew(Self.candidate(postedBy: Self.myUID, createdAt: Self.base.addingTimeInterval(1))))
    }

    /// NEW の数（0 件・複数件）
    @Test
    func newCount() {
        let later = Self.base.addingTimeInterval(10)
        let candidates = [
            Self.candidate(createdAt: later),
            Self.candidate(createdAt: later),
            Self.candidate(postedBy: Self.myUID, createdAt: later),
            Self.candidate(createdAt: Self.base.addingTimeInterval(-10))
        ]
        #expect(CandidateList.newCount(candidates, myUID: Self.myUID, lastSeenAt: Self.base) == 2)
        #expect(CandidateList.newCount(candidates, myUID: Self.myUID, lastSeenAt: later) == 0)
        #expect(CandidateList.newCount([], myUID: Self.myUID, lastSeenAt: Self.base) == 0)
    }
}
