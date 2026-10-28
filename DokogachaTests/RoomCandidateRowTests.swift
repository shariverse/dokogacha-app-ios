//
//  RoomCandidateRowTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 候補一覧の行（`RoomCandidateRow.rows`）の組み立て
struct RoomCandidateRowTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static func room(memberIds: [String], likeMode: LikeMode = .boost, status: RoomStatus = .open) -> Room {
        Room(
            name: "旅行",
            ownerId: memberIds.first ?? "",
            inviteCode: "DK729Q",
            status: status,
            settings: RoomSettings(postLimit: 3, unlockRule: .all, deadlineAt: nil, likeMode: likeMode),
            forcedUnlock: false,
            memberIds: memberIds,
            memberCount: memberIds.count,
            readyCount: 0,
            candidateCount: 1,
            adFreeSponsor: nil,
            currentDrawId: nil,
            winnerCandidateId: nil,
            excludedCandidateIds: [],
            reroll: .initial,
            createdAt: base,
            drawnAt: nil,
            closedAt: nil
        )
    }

    static func candidate(_ id: String, by postedBy: String, likedBy: [String], minutesAgo: Double = 0) -> Identified<Candidate> {
        Identified(id: id, value: Candidate(
            place: Place(name: "場所\(id)", area: "東京・豊島区", latitude: 35, longitude: 139, mapItemId: nil),
            category: .town,
            note: "",
            url: nil,
            postedBy: postedBy,
            postedByName: "投稿時の名前",
            colorIndex: 0,
            likedBy: likedBy,
            fromPastIdeaId: nil,
            createdAt: base.addingTimeInterval(-minutesAgo * 60)
        ))
    }

    /// 5 人のルームで投稿者以外の 3 人がいいね → 「みんな推し」、4 人 → 「全員いいね」（F-20〜23 の AC）
    @Test
    func popularityInFiveMemberRoom() {
        let room = Self.room(memberIds: ["me", "a", "b", "c", "d"])
        let rows = RoomCandidateRow.rows(
            candidates: [
                Self.candidate("three", by: "a", likedBy: ["b", "c", "d"], minutesAgo: 1),
                Self.candidate("four", by: "a", likedBy: ["me", "b", "c", "d"], minutesAgo: 2)
            ],
            members: [],
            room: room,
            myUserID: "me",
            lastSeenAt: nil
        )
        #expect(rows.map(\.highlight) == [.popular, .allLiked])
    }

    /// 送っている途中のいいねを映す（付けるなら足し、外すなら除く）。購読の値に同じものがあれば二重にしない
    @Test
    func pendingLikesAreApplied() {
        #expect(RoomCandidateRow.effectiveLikedBy(["a"], pending: true, myUserID: "me") == ["a", "me"])
        #expect(RoomCandidateRow.effectiveLikedBy(["a", "me"], pending: true, myUserID: "me") == ["a", "me"])
        #expect(RoomCandidateRow.effectiveLikedBy(["me", "a"], pending: false, myUserID: "me") == ["a"])
        #expect(RoomCandidateRow.effectiveLikedBy(["a"], pending: nil, myUserID: "me") == ["a"])
    }

    /// いいねボタンの状態: 自分の投稿は「自分」。`open`・`unlocked` は押せて、`drawn`・`closed` と引き直しで外れた候補は押せない
    @Test
    func likeStatusByRoomStatus() {
        func status(_ postedBy: String, liked: Bool, _ roomStatus: RoomStatus, excluded: Bool = false) -> DGLikeButton.Status {
            RoomCandidateRow.likeStatus(postedBy: postedBy, isLiked: liked, roomStatus: roomStatus, isExcluded: excluded, myUserID: "me")
        }
        for roomStatus in RoomStatus.allCases {
            #expect(status("me", liked: false, roomStatus) == .mine)
            #expect(status("me", liked: false, roomStatus, excluded: true) == .mine)
        }
        #expect(status("a", liked: false, .open) == .notLiked)
        #expect(status("a", liked: true, .unlocked) == .liked)
        #expect(status("a", liked: false, .drawn) == .locked)
        #expect(status("a", liked: true, .closed) == .lockedLiked)
        #expect(status("a", liked: false, .unlocked, excluded: true) == .locked)
        #expect(status("a", liked: true, .unlocked, excluded: true) == .lockedLiked)
    }

    /// 引き直しで外れた候補は、いいねが多くても人気の強調（リボン）を付けず、いいねも押せない。出やすさは対象外（PR #52 の持ち越し）
    @Test
    func excludedCandidateHasNoRibbonAndLockedLike() {
        var room = Self.room(memberIds: ["me", "a", "b", "c", "d"], status: .unlocked)
        room.excludedCandidateIds = ["four"]
        let rows = RoomCandidateRow.rows(
            candidates: [
                Self.candidate("three", by: "a", likedBy: ["b", "c", "d"], minutesAgo: 1),
                Self.candidate("four", by: "a", likedBy: ["me", "b", "c", "d"], minutesAgo: 2)
            ],
            members: [],
            room: room,
            myUserID: "me",
            lastSeenAt: nil
        )
        #expect(rows.map(\.highlight) == [.popular, nil])
        #expect(rows.map(\.likeStatus) == [.notLiked, .lockedLiked])
        #expect(rows[1].odds == nil)
        #expect(rows[1].likers.map(\.id) == ["me", "b", "c", "d"])
        #expect(rows[0].odds?.displayPercent == 100)
    }

    /// 投稿者: 自分・メンバー（今の表示名。メンバーを読む前は投稿時の名前）・退出した人
    @Test
    func authorNames() {
        let room = Self.room(memberIds: ["me", "a"])
        let member = Member(
            displayName: "はるか",
            avatarColor: AvatarPalette.colors[0],
            role: .member,
            ready: false,
            joinedAt: Self.base,
            lastSeenAt: Self.base
        )
        let candidates = [
            Self.candidate("mine", by: "me", likedBy: [], minutesAgo: 1),
            Self.candidate("member", by: "a", likedBy: [], minutesAgo: 2),
            Self.candidate("left", by: "gone", likedBy: [], minutesAgo: 3)
        ]
        let loaded = RoomCandidateRow.rows(
            candidates: candidates, members: [Identified(id: "a", value: member)], room: room, myUserID: "me", lastSeenAt: nil
        )
        #expect(loaded.map(\.author) == [.me, .member("はるか"), .departed])
        let notLoaded = RoomCandidateRow.rows(candidates: candidates, members: [], room: room, myUserID: "me", lastSeenAt: nil)
        #expect(notLoaded.map(\.author) == [.me, .member("投稿時の名前"), .departed])
    }

    /// `lastSeenAt` をまだ読めていなければ NEW にしない
    @Test
    func noNewBeforeLastSeenIsKnown() {
        let rows = RoomCandidateRow.rows(
            candidates: [Self.candidate("c", by: "a", likedBy: [])],
            members: [],
            room: Self.room(memberIds: ["me", "a"]),
            myUserID: "me",
            lastSeenAt: nil
        )
        #expect(rows.map(\.isNew) == [false])
    }
}
