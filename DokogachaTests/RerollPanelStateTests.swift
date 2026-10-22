//
//  RerollPanelStateTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-14 の引き直しの欄（`RerollPanelState`）が、ルームの状態ごとに 02 の §6.4 の表示になることを確かめる
struct RerollPanelStateTests {
    /// 4 人の `drawn` のルーム（抽選 "draw1"・提案前）
    static func room(
        status: RoomStatus = .drawn,
        reroll: RerollState = .initial,
        currentDrawId: String = "draw1"
    ) -> Room {
        var room = DomainModelsTests.sampleRoom()
        room.status = status
        room.memberIds = ["me", "a", "b", "c"]
        room.memberCount = 4
        room.currentDrawId = currentDrawId
        room.reroll = reroll
        return room
    }

    /// 投票中の引き直し
    static func voting(for votesFor: [String], against votesAgainst: [String] = []) -> RerollState {
        RerollState(
            used: true, proposedBy: votesFor.first, proposedAt: nil, votesFor: votesFor, votesAgainst: votesAgainst, status: .voting
        )
    }

    /// 使い終えた引き直し
    static func finished(_ status: RerollStatus) -> RerollState {
        RerollState(used: true, proposedBy: "a", proposedAt: nil, votesFor: ["a"], votesAgainst: [], status: status)
    }

    static func make(_ room: Room?, drawID: String = "draw1") -> RerollPanelState {
        RerollPanelState.make(room: room, drawID: drawID, userID: "me")
    }

    /// 提案前の `drawn` で、出している抽選が今の抽選なら提案できる
    @Test
    func proposableBeforeProposal() {
        #expect(Self.make(Self.room()) == .proposable)
    }

    /// 投票中は「賛成を集めています…（N/M人）」の N（今のメンバーの賛成）と M（メンバーの数）、自分の票
    @Test
    func votingShowsCountsAndMyVote() {
        #expect(Self.make(Self.room(reroll: Self.voting(for: ["a"]))) == .voting(approvals: 1, memberCount: 4, myVote: nil))
        #expect(Self.make(Self.room(reroll: Self.voting(for: ["a", "me"]))) == .voting(approvals: 2, memberCount: 4, myVote: .approve))
        let rejected = Self.make(Self.room(reroll: Self.voting(for: ["a"], against: ["me"])))
        #expect(rejected == .voting(approvals: 1, memberCount: 4, myVote: .reject))
        // 退出した人の票は数えない
        #expect(Self.make(Self.room(reroll: Self.voting(for: ["a", "left"]))) == .voting(approvals: 1, memberCount: 4, myVote: nil))
    }

    /// 可決して unlocked に戻ったら「もう一度引けます」。ほかの人が回し直した後も、前の抽選を出していれば同じ
    @Test
    func passedUntilRedrawn() {
        #expect(Self.make(Self.room(status: .unlocked, reroll: Self.finished(.passed))) == .passed)
        #expect(Self.make(Self.room(reroll: Self.finished(.passed), currentDrawId: "draw2")) == .passed)
    }

    /// 可決の後に回し直した結果・否決の後は「引き直しは使用済みです」
    @Test
    func usedAfterRedrawOrRejection() {
        #expect(Self.make(Self.room(reroll: Self.finished(.passed), currentDrawId: "draw2"), drawID: "draw2") == .used)
        #expect(Self.make(Self.room(reroll: Self.finished(.rejected))) == .used)
        // 権利を使った印があれば、状態が none でも使用済み
        var used = RerollState.initial
        used.used = true
        #expect(Self.make(Self.room(reroll: used)) == .used)
        // 前の抽選を出している（提案前のまま回し直された壊れた状態）なら提案させない
        #expect(Self.make(Self.room(currentDrawId: "draw2")) == .used)
    }

    /// closed は閲覧のみで出さない。ルームを読めていない・行き先が決まる前も出さない
    @Test
    func hiddenWhenReadOnlyOrNotDrawn() {
        #expect(Self.make(Self.room(status: .closed)) == .hidden)
        #expect(Self.make(Self.room(status: .closed, reroll: Self.voting(for: ["a"]))) == .hidden)
        #expect(Self.make(nil) == .hidden)
        #expect(Self.make(Self.room(status: .unlocked)) == .hidden)
        #expect(Self.make(Self.room(status: .open)) == .hidden)
    }
}
