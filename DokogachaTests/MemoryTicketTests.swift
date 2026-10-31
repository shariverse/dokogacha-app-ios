//
//  MemoryTicketTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ホームの思い出のきっぷ（`MemoryTicket`。03 の S-02 の 3・F-44）の並び・出す条件・外れた候補の数・「すべて見る」
struct MemoryTicketTests {
    static let base = Date(timeIntervalSince1970: 1_793_070_000)

    /// 終了したルーム（`daysAgo` 日前に終了。候補は `candidates` 件）
    static func closedRoom(
        _ id: String,
        daysAgo: Double,
        candidates: Int = 3,
        status: RoomStatus = .closed,
        drawID: String? = "draw"
    ) -> Identified<Room> {
        var room = RoomClosingTests.room(status)
        room.name = "ルーム\(id)"
        room.candidateCount = candidates
        room.currentDrawId = drawID
        room.closedAt = status == .closed ? base.addingTimeInterval(-daysAgo * 86_400) : nil
        room.drawnAt = base.addingTimeInterval(-(daysAgo + 1) * 86_400)
        return Identified(id: id, value: room)
    }

    /// 当選した候補（ルームの ID ごと）
    static func winners(_ ids: [String]) -> [String: Candidate] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, RoomClosingTests.candidate("城ヶ島\($0)")) })
    }

    /// 終了の日時の新しい順に並べ、ルーム名・日付・当選場所・外れた候補の数（候補 − 1）を出す
    @Test
    func ticketsAreNewestFirst() {
        let rooms = [Self.closedRoom("a", daysAgo: 30), Self.closedRoom("b", daysAgo: 3, candidates: 5), Self.closedRoom("c", daysAgo: 10)]
        let tickets = MemoryTicket.tickets(rooms: rooms, winners: Self.winners(["a", "b", "c"]))
        #expect(tickets.map(\.id) == ["b", "c", "a"])
        let first = tickets[0]
        #expect(first.roomName == "ルームb")
        #expect(first.destinationName == "城ヶ島b")
        #expect(first.date == Self.base.addingTimeInterval(-3 * 86_400))
        #expect(first.leftoverCount == 4)
        #expect(first.drawID == "draw")
    }

    /// 当選した候補が届いていない・抽選の ID が無い・closed でないルームは出さない。候補が 1 件なら外れた候補は 0
    @Test
    func skipsIncompleteRooms() {
        let rooms = [
            Self.closedRoom("ok", daysAgo: 1, candidates: 1),
            Self.closedRoom("noWinner", daysAgo: 2),
            Self.closedRoom("noDraw", daysAgo: 3, drawID: nil),
            Self.closedRoom("drawn", daysAgo: 4, status: .drawn)
        ]
        let tickets = MemoryTicket.tickets(rooms: rooms, winners: Self.winners(["ok", "noDraw", "drawn"]))
        #expect(tickets.map(\.id) == ["ok"])
        #expect(tickets.first?.leftoverCount == 0)
    }

    /// 行き先が決まらないまま終了したルーム（引き直しの可決の後に途中で終了した・抽選の前に終了した）は、
    /// 当選した候補が届いてもきっぷに出さず、待たない（過去のアイデアも登録しないため。Discussion #155 の Q4）
    @Test
    func skipsRoomsClosedWithoutDecidedWinner() {
        var rerolled = Self.closedRoom("rerolled", daysAgo: 1)
        rerolled.value.excludedCandidateIds = [rerolled.value.winnerCandidateId ?? ""]
        var early = Self.closedRoom("early", daysAgo: 2, drawID: nil)
        early.value.winnerCandidateId = nil
        let rooms = [rerolled, early, Self.closedRoom("decided", daysAgo: 3)]

        let tickets = MemoryTicket.tickets(rooms: rooms, winners: Self.winners(["rerolled", "early", "decided"]))
        #expect(tickets.map(\.id) == ["decided"])
        #expect(!MemoryTicket.canBecomeTicket(rerolled.value))
        #expect(!MemoryTicket.canBecomeTicket(early.value))
        #expect(!MemoryTicket.isWaitingForWinners(watched: [rerolled, early], settledRoomIDs: []))
    }

    /// 読んだ 6 件にきっぷにならないルームが混ざっていたら、上限なしで読み直す。購読する枠もきっぷになるルームだけで使う（Discussion #155）
    @Test
    func readsAllWhenRoomsEndedWithoutResultAreMixed() {
        #expect(MemoryTicket.needsAllRooms(roomCount: 6, ticketRoomCount: 5))
        #expect(MemoryTicket.needsAllRooms(roomCount: 6, ticketRoomCount: 0))
        #expect(!MemoryTicket.needsAllRooms(roomCount: 6, ticketRoomCount: 6))
        #expect(!MemoryTicket.needsAllRooms(roomCount: 5, ticketRoomCount: 3))

        var early = Self.closedRoom("early", daysAgo: 1, drawID: nil)
        early.value.winnerCandidateId = nil
        let rooms = [early] + (1...5).map { Self.closedRoom("r\($0)", daysAgo: Double($0 + 1)) }
        #expect(MemoryTicket.watchedRooms(rooms, showsAll: false).map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
    }

    /// 当選した候補を待つのは、きっぷになりうるルームで、購読がまだ値も失敗も受け取っていないものがある間だけ（PR #78 の持ち越し）
    @Test
    func waitsOnlyForUnsettledWinners() {
        let rooms = [Self.closedRoom("a", daysAgo: 1), Self.closedRoom("b", daysAgo: 2), Self.closedRoom("noDraw", daysAgo: 3, drawID: nil)]
        #expect(MemoryTicket.isWaitingForWinners(watched: rooms, settledRoomIDs: []))
        #expect(MemoryTicket.isWaitingForWinners(watched: rooms, settledRoomIDs: ["a"]))
        // 抽選の ID が無いルームはきっぷにならないので待たない
        #expect(!MemoryTicket.isWaitingForWinners(watched: rooms, settledRoomIDs: ["a", "b"]))
        #expect(!MemoryTicket.isWaitingForWinners(watched: [], settledRoomIDs: []))
    }

    /// 5 枚までを出し、6 枚目からは「すべて見る」を押すと出す（03 の S-02「最大5件表示＋「すべて見る」」）
    @Test
    func showsFiveUntilShowAll() {
        let ids = (1...6).map { "r\($0)" }
        let rooms = ids.enumerated().map { Self.closedRoom($1, daysAgo: Double($0)) }
        let tickets = MemoryTicket.tickets(rooms: rooms, winners: Self.winners(ids))
        #expect(MemoryTicket.visibleLimit == 5)
        #expect(MemoryTicket.visible(tickets, showsAll: false).map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
        #expect(MemoryTicket.hasMore(roomCount: 6, showsAll: false))
        #expect(MemoryTicket.visible(tickets, showsAll: true).count == 6)
        #expect(!MemoryTicket.hasMore(roomCount: 6, showsAll: true))
        #expect(!MemoryTicket.hasMore(roomCount: 5, showsAll: false))
    }

    /// 「すべて見る」を押す前は 6 件だけ読み、当選した候補は先頭の 5 つだけ購読する。押した後はすべて
    @Test
    func watchesOnlyVisibleRooms() {
        let rooms = (1...6).enumerated().map { Self.closedRoom("r\($1)", daysAgo: Double($0)) }
        #expect(MemoryTicket.queryLimit == 6)
        #expect(MemoryTicket.watchedRooms(rooms, showsAll: false).map(\.id) == ["r1", "r2", "r3", "r4", "r5"])
        #expect(MemoryTicket.watchedRooms(rooms, showsAll: true).count == 6)
        #expect(MemoryTicket.watchedRooms(Array(rooms.prefix(2)), showsAll: false).count == 2)
    }
}
