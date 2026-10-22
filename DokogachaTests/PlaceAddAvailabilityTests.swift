//
//  PlaceAddAvailabilityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の検索結果の行の「追加」「追加済み」「上限」と、重複の確認へ回す判定（02 の F-10 の上限・重複・状態）を確かめる
struct PlaceAddAvailabilityTests {
    static let me = "me"
    static let other = "other"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static let aquarium = Place(name: "すみだ水族館", area: "東京・墨田区", latitude: 35.710_1, longitude: 139.810_7, mapItemId: nil)
    static let shrine = Place(name: "明治神宮", area: "東京・渋谷区", latitude: 35.676_4, longitude: 139.699_3, mapItemId: nil)
    static let sea = Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.299_4, longitude: 139.480_0, mapItemId: nil)

    static func candidate(_ id: String, _ place: Place, by userID: String) -> Identified<Candidate> {
        Identified(
            id: id,
            value: Candidate(
                place: place,
                category: .town,
                note: "",
                url: nil,
                postedBy: userID,
                postedByName: userID,
                colorIndex: 0,
                likedBy: [],
                fromPastIdeaId: nil,
                createdAt: now
            )
        )
    }

    static func availability(
        _ place: Place,
        _ candidates: [Identified<Candidate>],
        postLimit: Int = 3,
        accepts: Bool = true
    ) -> PlaceAddAvailability {
        PlaceAddAvailability.of(place, candidates: candidates, userID: me, postLimit: postLimit, acceptsCandidates: accepts)
    }

    /// 同じ場所が無く、上限に達していなければ「追加」
    @Test
    func addableWhenNewAndUnderLimit() {
        let candidates = [Self.candidate("c1", Self.shrine, by: Self.other)]
        #expect(Self.availability(Self.aquarium, candidates) == .addable)
        #expect(Self.availability(Self.aquarium, candidates).isEnabled)
    }

    /// 自分が投稿した場所は「追加済み」（押せない）。上限に達していても「追加済み」を出す
    @Test
    func ownPostIsAdded() {
        let candidates = [Self.candidate("c1", Self.sea, by: Self.me)]
        #expect(Self.availability(Self.sea, candidates) == .added)
        #expect(Self.availability(Self.sea, candidates, postLimit: 1) == .added)
        #expect(!PlaceAddAvailability.added.isEnabled)
    }

    /// ほかの人が投稿した場所は重複の確認に回す（押せる。値は既存の候補）。100m 以内の同じ名前も同じ場所
    @Test
    func othersPostIsDuplicate() {
        var nearby = Self.shrine
        nearby.latitude += 0.000_5
        let candidates = [Self.candidate("c1", nearby, by: Self.other)]
        #expect(Self.availability(Self.shrine, candidates) == .duplicate(candidateID: "c1"))
        #expect(Self.availability(Self.shrine, candidates).isEnabled)
    }

    /// 自分の投稿数が上限に達していたら、新しい場所は「上限」（押せない。02 の F-10）
    @Test
    func limitReachedDisablesNewPlaces() {
        let candidates = [
            Self.candidate("c1", Self.sea, by: Self.me),
            Self.candidate("c2", Self.shrine, by: Self.other)
        ]
        #expect(Self.availability(Self.aquarium, candidates, postLimit: 1) == .limitReached)
        #expect(!PlaceAddAvailability.limitReached.isEnabled)
        #expect(Self.availability(Self.aquarium, candidates, postLimit: 2) == .addable)
    }

    /// 判定の順は backend の `decideAddCandidate` と同じ「重複 → 上限」。上限に達していても、ほかの人の重複は重複の確認に回す
    /// （上限の人もいいねできる）。自分の投稿は上限でも「追加済み」
    @Test
    func duplicateIsCheckedBeforeLimit() {
        let candidates = [
            Self.candidate("c1", Self.sea, by: Self.me),
            Self.candidate("c2", Self.shrine, by: Self.other)
        ]
        #expect(Self.availability(Self.shrine, candidates, postLimit: 1) == .duplicate(candidateID: "c2"))
        #expect(Self.availability(Self.sea, candidates, postLimit: 1) == .added)
    }

    /// 投稿を受け付けない状態（`drawn`・`closed`・ルームが届いていない）では押せない
    @Test
    func unavailableWhenRoomDoesNotAccept() {
        #expect(Self.availability(Self.aquarium, [], accepts: false) == .unavailable)
        #expect(Self.availability(Self.sea, [Self.candidate("c1", Self.sea, by: Self.me)], accepts: false) == .unavailable)
        #expect(!PlaceAddAvailability.unavailable.isEnabled)
    }

    /// 自分の投稿の数を数える
    @Test
    func countsMyPosts() {
        let candidates = [
            Self.candidate("c1", Self.sea, by: Self.me),
            Self.candidate("c2", Self.shrine, by: Self.other),
            Self.candidate("c3", Self.aquarium, by: Self.me)
        ]
        #expect(PlaceAddAvailability.myPostCount(in: candidates, userID: Self.me) == 2)
        #expect(PlaceAddAvailability.myPostCount(in: [], userID: Self.me) == 0)
    }
}
