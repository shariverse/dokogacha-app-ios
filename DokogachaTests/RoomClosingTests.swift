//
//  RoomClosingTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ルームの終了の判定（`RoomClosing`。F-44）。過去のアイデアの作り方は backend の `close/logic.test.ts` の `planPastIdeas` と同じケース
struct RoomClosingTests {
    static let closedAt = Date(timeIntervalSince1970: 1_793_070_000)

    /// alice が作成者で、alice・bob がメンバー。c1 が当選したルーム
    static func room(_ status: RoomStatus, members: [String] = ["alice", "bob"], winner: String? = "c1") -> Room {
        Room(
            name: "年末の旅行",
            ownerId: "alice",
            inviteCode: "DK729Q",
            status: status,
            settings: RoomSettings(postLimit: 3, unlockRule: .all, deadlineAt: nil, likeMode: .boost),
            forcedUnlock: false,
            memberIds: members,
            memberCount: members.count,
            readyCount: 0,
            candidateCount: 3,
            adFreeSponsor: nil,
            currentDrawId: "d1",
            winnerCandidateId: winner,
            excludedCandidateIds: [],
            reroll: .initial,
            createdAt: closedAt,
            drawnAt: closedAt,
            closedAt: status == .closed ? closedAt : nil
        )
    }

    /// 候補（`likedBy` の数がいいね数）
    static func candidate(_ name: String, likedBy: [String] = [], category: PlaceCategory = .aquarium) -> Candidate {
        Candidate(
            place: Place(name: name, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: nil),
            category: category,
            note: "",
            url: nil,
            postedBy: "bob",
            postedByName: "bob",
            colorIndex: 0,
            likedBy: likedBy,
            fromPastIdeaId: nil,
            createdAt: closedAt
        )
    }

    /// 作成者には drawn のときだけ「この行き先で決定」、作成者以外には説明を出す
    @Test
    func footerDependsOnOwnerAndStatus() {
        #expect(RoomClosing.footer(for: Self.room(.drawn), userID: "alice") == .decide)
        #expect(RoomClosing.footer(for: Self.room(.drawn), userID: "bob") == .waitingForOwner)
        for status in [RoomStatus.open, .unlocked, .closed] {
            #expect(RoomClosing.footer(for: Self.room(status), userID: "alice") == .hidden)
            #expect(RoomClosing.footer(for: Self.room(status), userID: "bob") == .hidden)
        }
    }

    /// closeRoom の状態と意図の突き合わせ（backend の `close/logic.test.ts` の `decideClose` と同じケース）
    @Test
    func decisionMatchesStatusAndReason() {
        #expect(RoomClosing.decision(status: .drawn, reason: .decide) == .close)
        #expect(RoomClosing.decision(status: .open, reason: .decide) == .reject(.roomNotDrawn))
        #expect(RoomClosing.decision(status: .unlocked, reason: .decide) == .reject(.roomNotDrawn))
        #expect(RoomClosing.decision(status: .open, reason: .endEarly) == .close)
        #expect(RoomClosing.decision(status: .unlocked, reason: .endEarly) == .close)
        #expect(RoomClosing.decision(status: .drawn, reason: .endEarly) == .reject(.roomAlreadyDecided))
        #expect(RoomClosing.decision(status: .closed, reason: .decide) == .alreadyClosed)
        #expect(RoomClosing.decision(status: .closed, reason: .endEarly) == .alreadyClosed)
    }

    /// closeRoom の入力は backend の `parseCloseRoomInput` が読む形（`{ roomId, reason }`。意図は `decide`・`endEarly`）
    @Test
    func closeRoomRequestEncodesReason() throws {
        let data = try JSONEncoder().encode(CloseRoomRequest(roomId: "r1", reason: .endEarly))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["roomId": "r1", "reason": "endEarly"])
        #expect(CloseRoomRequest.Reason.decide.rawValue == "decide")
    }

    /// 当選以外の候補を、各メンバーに登録する（自分以外の投稿も・引き直しで外れた前の当選も）
    @Test
    func pastIdeasAreLosersForEveryMember() throws {
        let writes = RoomClosing.pastIdeas(
            roomID: "room1",
            room: Self.room(.closed),
            candidates: [
                "c2": Self.candidate("江の島", likedBy: ["alice", "bob", "carol"], category: .sea),
                "c1": Self.candidate("サンシャイン水族館", likedBy: ["bob"]),
                "c3": Self.candidate("明治神宮", category: .shrine)
            ],
            closedAt: Self.closedAt
        )
        #expect(writes.map { [$0.userID, $0.ideaID] } == [
            ["alice", "room1_c2"], ["alice", "room1_c3"], ["bob", "room1_c2"], ["bob", "room1_c3"]
        ])
        let first = try #require(writes.first?.idea)
        #expect(first == PastIdea(
            sourceRoomId: "room1",
            sourceRoomName: "年末の旅行",
            sourceClosedAt: Self.closedAt,
            sourceWinnerName: "サンシャイン水族館",
            place: Place(name: "江の島", area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: nil),
            category: .sea,
            prevLikeCount: 3
        ))
        #expect(writes[1].idea.prevLikeCount == 0)
    }

    /// 候補が当選の 1 件だけなら何も登録しない・同じ uid は 1 回・メンバーがいなければ登録しない
    @Test
    func pastIdeasEdgeCases() {
        let onlyWinner = ["c1": Self.candidate("城ヶ島")]
        #expect(RoomClosing.pastIdeas(roomID: "room1", room: Self.room(.closed), candidates: onlyWinner, closedAt: Self.closedAt).isEmpty)
        let two = ["c1": Self.candidate("城ヶ島"), "c2": Self.candidate("江の島")]
        let duplicated = Self.room(.closed, members: ["alice", "alice"])
        #expect(RoomClosing.pastIdeas(roomID: "room1", room: duplicated, candidates: two, closedAt: Self.closedAt).count == 1)
        let empty = Self.room(.closed, members: [])
        #expect(RoomClosing.pastIdeas(roomID: "room1", room: empty, candidates: two, closedAt: Self.closedAt).isEmpty)
    }

    /// 当選の候補が見つからなければ、当選の名前は空のまま、すべての候補を登録する。終了の日時が無ければ引数の日時を使う
    @Test
    func pastIdeasWithMissingWinnerCandidate() {
        var room = Self.room(.closed, members: ["alice"], winner: "c9")
        room.closedAt = nil
        let later = Self.closedAt.addingTimeInterval(60)
        let writes = RoomClosing.pastIdeas(
            roomID: "room1",
            room: room,
            candidates: ["c2": Self.candidate("江の島"), "c1": Self.candidate("城ヶ島")],
            closedAt: later
        )
        #expect(writes.map(\.ideaID) == ["room1_c1", "room1_c2"])
        #expect(writes.allSatisfy { $0.idea.sourceWinnerName.isEmpty && $0.idea.sourceClosedAt == later })
    }

    /// 行き先が決まらないまま終了したルームは登録しない（backend の `hasDecidedWinner`・`planPastIdeas` と同じケース。Discussion #155 の Q4）
    @Test
    func pastIdeasSkipRoomsClosedWithoutDecidedWinner() {
        let two = ["c1": Self.candidate("城ヶ島"), "c2": Self.candidate("江の島")]
        // 抽選の前に途中で終了した（当選が無い）
        let early = Self.room(.closed, winner: nil)
        #expect(!RoomClosing.hasDecidedWinner(early))
        #expect(RoomClosing.pastIdeas(roomID: "room1", room: early, candidates: two, closedAt: Self.closedAt).isEmpty)
        #expect(!RoomClosing.hasDecidedWinner(Self.room(.closed, winner: "")))
        // 引き直しが可決して unlocked に戻ったまま終了した（前の当選 c1 は外した候補）
        var rerolled = Self.room(.closed)
        rerolled.excludedCandidateIds = ["c1"]
        #expect(!RoomClosing.hasDecidedWinner(rerolled))
        #expect(RoomClosing.pastIdeas(roomID: "room1", room: rerolled, candidates: two, closedAt: Self.closedAt).isEmpty)
        // 引き直した後の当選（前の当選だけを外した）は行き先がある
        var redrawn = Self.room(.closed, members: ["alice"], winner: "c2")
        redrawn.excludedCandidateIds = ["c1"]
        #expect(RoomClosing.hasDecidedWinner(redrawn))
        let redrawnWrites = RoomClosing.pastIdeas(roomID: "room1", room: redrawn, candidates: two, closedAt: Self.closedAt)
        #expect(redrawnWrites.map(\.ideaID) == ["room1_c1"])
    }

    /// 過去のアイデアの ID は元のルームと候補から決まる（backend の `pastIdeaId`）
    @Test
    func pastIdeaIDIsDeterministic() {
        #expect(RoomClosing.pastIdeaID(roomID: "room1", candidateID: "c2") == "room1_c2")
    }
}
