//
//  AnalyticsEventTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// Analytics のイベントの名前とパラメータが 05 の §9 の表の綴りどおりで、自由入力の文字を含まないことを確かめる
struct AnalyticsEventTests {
    // MARK: 名前とパラメータ（05 の §9）

    @Test
    func roomCreate() {
        let event = AnalyticsEvent.roomCreate(postLimit: 3, unlockRule: .majority, likeMode: .equal)
        #expect(event.name == "room_create")
        #expect(event.parameters == ["post_limit": .int(3), "unlock_rule": .string("majority"), "like_mode": .string("equal")])
    }

    @Test(arguments: RoomJoinVia.allCases)
    func roomJoin(via: RoomJoinVia) {
        let event = AnalyticsEvent.roomJoin(via: via)
        #expect(event.name == "room_join")
        #expect(event.parameters == ["via": .string(via.rawValue)])
    }

    /// `via` の値は 05 の §9 の link / code / push
    @Test
    func joinViaValues() {
        #expect(RoomJoinVia.allCases.map(\.rawValue) == ["link", "code", "push"])
    }

    @Test
    func candidateAdd() {
        let event = AnalyticsEvent.candidateAdd(source: .past, category: .shrine)
        #expect(event.name == "candidate_add")
        #expect(event.parameters == ["source": .string("past"), "category": .string("shrine")])
        #expect(CandidateAddSource.allCases.map(\.rawValue) == ["search", "past"])
    }

    /// 真偽は 1・0 の数で送る
    @Test
    func likeAndReadyToggle() {
        #expect(AnalyticsEvent.likeToggle(on: true).name == "like_toggle")
        #expect(AnalyticsEvent.likeToggle(on: true).parameters == ["on": .int(1)])
        #expect(AnalyticsEvent.likeToggle(on: false).parameters == ["on": .int(0)])
        #expect(AnalyticsEvent.readyToggle(on: true).name == "ready_toggle")
        #expect(AnalyticsEvent.readyToggle(on: false).parameters == ["on": .int(0)])
    }

    @Test
    func roomUnlock() {
        let event = AnalyticsEvent.roomUnlock(rule: .deadline, forced: true)
        #expect(event.name == "room_unlock")
        #expect(event.parameters == ["rule": .string("deadline"), "forced": .int(1)])
    }

    @Test
    func gachaDraw() {
        let event = AnalyticsEvent.gachaDraw(candidateCount: 7, isReroll: true, rare: false)
        #expect(event.name == "gacha_draw")
        #expect(event.parameters == ["candidate_count": .int(7), "is_reroll": .int(1), "rare": .int(0)])
    }

    @Test
    func rerollAndClose() {
        #expect(AnalyticsEvent.rerollPropose.name == "reroll_propose")
        #expect(AnalyticsEvent.rerollPropose.parameters.isEmpty)
        #expect(AnalyticsEvent.rerollResult(passed: true).name == "reroll_result")
        #expect(AnalyticsEvent.rerollResult(passed: false).parameters == ["passed": .int(0)])
        #expect(AnalyticsEvent.roomClose(auto: false, early: false).name == "room_close")
        #expect(AnalyticsEvent.roomClose(auto: false, early: false).parameters == ["auto": .int(0), "early": .int(0)])
        #expect(AnalyticsEvent.roomClose(auto: false, early: true).parameters == ["auto": .int(0), "early": .int(1)])
    }

    /// パラメータの無いイベント
    @Test
    func eventsWithoutParameters() {
        #expect(AnalyticsEvent.ticketShare.name == "ticket_share")
        #expect(AnalyticsEvent.ticketShare.parameters.isEmpty)
        #expect(AnalyticsEvent.purchaseRemoveAds.name == "purchase_remove_ads")
        #expect(AnalyticsEvent.purchaseRemoveAds.parameters.isEmpty)
    }

    // MARK: ルームの変化（解禁・引き直しの結果）

    static func room(status: RoomStatus, rule: UnlockRule = .all, forced: Bool = false, reroll: RerollStatus = .notProposed) -> Room {
        var room = HomeRoomCardTests.room(name: "年末の旅行", status: status, createdAt: HomeRoomCardTests.base)
        room.settings.unlockRule = rule
        room.forcedUnlock = forced
        room.reroll.status = reroll
        return room
    }

    /// `open` → `unlocked` を見たら、解禁の条件と強制解禁かを送る
    @Test
    func unlockTransition() {
        let events = AnalyticsEvent.roomChanges(
            previous: Self.room(status: .open, rule: .majority),
            current: Self.room(status: .unlocked, rule: .majority, forced: true)
        )
        #expect(events == [.roomUnlock(rule: .majority, forced: true)])
    }

    /// 画面を開いたときの最初の値・変わっていない値・引き直しで `unlocked` に戻ったときは送らない
    @Test
    func noUnlockWithoutTransitionFromOpen() {
        #expect(AnalyticsEvent.roomChanges(previous: nil, current: Self.room(status: .unlocked)).isEmpty)
        #expect(AnalyticsEvent.roomChanges(previous: Self.room(status: .unlocked), current: Self.room(status: .unlocked)).isEmpty)
        let rerolled = AnalyticsEvent.roomChanges(
            previous: Self.room(status: .drawn, reroll: .passed),
            current: Self.room(status: .unlocked, reroll: .passed)
        )
        #expect(rerolled.isEmpty)
    }

    /// 引き直しの投票中 → 可決・否決を見たら、結果を送る
    @Test
    func rerollResultTransition() {
        let passed = AnalyticsEvent.roomChanges(
            previous: Self.room(status: .drawn, reroll: .voting),
            current: Self.room(status: .unlocked, reroll: .passed)
        )
        #expect(passed == [.rerollResult(passed: true)])
        let rejected = AnalyticsEvent.roomChanges(
            previous: Self.room(status: .drawn, reroll: .voting),
            current: Self.room(status: .drawn, reroll: .rejected)
        )
        #expect(rejected == [.rerollResult(passed: false)])
        #expect(AnalyticsEvent.roomChanges(previous: nil, current: Self.room(status: .drawn, reroll: .rejected)).isEmpty)
    }

    // MARK: ガチャ（レア当選）

    static func candidates(likes: [String: Int]) -> [Identified<Candidate>] {
        likes.map { id, count in
            var candidate = CandidateRulesTests.candidate(id, CandidateRulesTests.enoshima, createdAtMs: 1_000).value
            candidate.likedBy = (0..<count).map { "u\($0)" }
            return Identified(id: id, value: candidate)
        }
    }

    /// 共感ブーストで、いいねの少ない候補（確率が平均の 0.85 倍未満）が当たればレア当選
    @Test
    func rareWinInBoost() {
        var room = Self.room(status: .unlocked)
        room.excludedCandidateIds = []
        let event = AnalyticsEvent.gachaDraw(winnerID: "c0", candidates: Self.candidates(likes: ["c0": 0, "c1": 4, "c2": 4]), room: room)
        #expect(event == .gachaDraw(candidateCount: 3, isReroll: false, rare: true))
        let popular = AnalyticsEvent.gachaDraw(winnerID: "c1", candidates: Self.candidates(likes: ["c0": 0, "c1": 4, "c2": 4]), room: room)
        #expect(popular == .gachaDraw(candidateCount: 3, isReroll: false, rare: false))
    }

    /// 引き直しの抽選は、外れた候補を数に入れず `is_reroll` を 1 にする。みんな平等ではレア当選にならない
    @Test
    func rerollExcludesCandidates() {
        var room = Self.room(status: .unlocked)
        room.settings.likeMode = .equal
        room.excludedCandidateIds = ["c2"]
        let event = AnalyticsEvent.gachaDraw(winnerID: "c0", candidates: Self.candidates(likes: ["c0": 0, "c1": 4, "c2": 4]), room: room)
        #expect(event == .gachaDraw(candidateCount: 2, isReroll: true, rare: false))
    }
}
