//
//  InMemoryServerDrawTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `drawGacha` が、backend と同じ検証・状態遷移をすることを確かめる
/// （backend の `test/emulator/draw.test.ts`・`draw/logic.test.ts` と同じ観点）
struct InMemoryServerDrawTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// 抽選の乱数（`GachaDraw.randomRange` を渡されたときに返す値。テストの途中で変えられる）
    final class DrawRandom {
        var value = 0
    }

    /// 作成者 "owner" でサインインした擬似のサーバー。
    ///
    /// 抽選の乱数は `random.value`。招待コード・アバターの色の乱数は呼ぶたびに 1 つずつ進める（招待コードが重ならないように）
    static func makeServer(random: DrawRandom = DrawRandom()) -> InMemoryServer {
        var counter = 0
        var other = 0
        return InMemoryServer(
            clock: { now },
            randomIndex: { upperBound in
                if upperBound == GachaDraw.randomRange {
                    return random.value
                }
                other += 1
                return other % upperBound
            },
            makeID: {
                counter += 1
                return "id-\(String(format: "%03d", counter))"
            },
            signedInUserID: "owner"
        )
    }

    /// "owner"・"bob"・"carol" のルームに、bob が 3 件（いいね 2・1・0）の候補を投稿した状態。`ready` の人が準備OK（既定は全員）
    static func makeRoom(
        _ server: InMemoryServer,
        ready: [String] = ["owner", "bob", "carol"]
    ) async throws -> (roomID: String, candidates: [String]) {
        let roomID = try await InMemoryServerUnlockTests.makeRoom(server, ready: ready)
        var candidates: [String] = []
        for name in ["江の島", "鎌倉", "葉山"] {
            let place = InMemoryServerCandidateTests.place(named: name)
            candidates.append(try await InMemoryServerCandidateTests.add(server, "bob", roomID, place: place))
        }
        server.rooms[roomID]?.candidates[candidates[0]]?.likedBy = ["owner", "carol"]
        server.rooms[roomID]?.candidates[candidates[1]]?.likedBy = ["owner"]
        return (roomID, candidates)
    }

    /// 解禁したルームで回すと、抽選の記録を作ってルームを drawn にする（05 の §3 のフィールド）
    @Test
    func drawWritesRecordAndRoom() async throws {
        let server = Self.makeServer()
        let (roomID, candidates) = try await Self.makeRoom(server)
        #expect(server.rooms[roomID]?.room.status == .unlocked)

        let response = try await server.device(of: "carol").drawGacha(RoomRequest(roomId: roomID))
        #expect(response.candidateId == candidates[0])
        #expect(!response.alreadyDrawn)
        let record = try #require(server.rooms[roomID])
        #expect(record.room.status == .drawn)
        #expect(record.room.currentDrawId == response.drawId)
        #expect(record.room.winnerCandidateId == candidates[0])
        #expect(record.room.drawnAt == Self.now)
        let inputs = zip(candidates, [2, 1, 0]).map { OddsInput(id: $0, likeCount: $1) }
        let odds = try #require(Probability.odds(of: inputs, mode: .boost)[candidates[0]])
        #expect(record.draws[response.drawId] == Draw(
            candidateId: candidates[0],
            probability: odds.probability,
            weights: [candidates[0]: 1 + 2.0.squareRoot(), candidates[1]: 2, candidates[2]: 1],
            drawnBy: "carol",
            drawnByName: "carol",
            isReroll: false,
            createdAt: Self.now
        ))
    }

    /// 乱数で区間の終わりを引くと、ID 順の最後の候補が当たる
    @Test
    func lastIntervalWinsLastCandidate() async throws {
        let random = DrawRandom()
        random.value = GachaDraw.randomRange - 1
        let server = Self.makeServer(random: random)
        let (roomID, candidates) = try await Self.makeRoom(server)
        #expect(try await server.drawGacha(RoomRequest(roomId: roomID)).candidateId == candidates[2])
    }

    /// 2 回目は抽選せずに同じ drawId を返し、記録は 1 件のまま（02 の §6.1「2人目には既存の結果を返す」）
    @Test
    func secondDrawReturnsSameResult() async throws {
        let random = DrawRandom()
        let server = Self.makeServer(random: random)
        let (roomID, _) = try await Self.makeRoom(server)
        let first = try await server.drawGacha(RoomRequest(roomId: roomID))
        random.value = GachaDraw.randomRange - 1
        let second = try await server.device(of: "bob").drawGacha(RoomRequest(roomId: roomID))
        #expect(second == DrawGachaResponse(drawId: first.drawId, candidateId: first.candidateId, alreadyDrawn: true))
        #expect(server.rooms[roomID]?.draws.count == 1)
    }

    /// メンバーでない・ルームが無い・入力が正しくないときは断る（何も書かない）
    @Test
    func rejectsNonMemberAndBadInput() async throws {
        let server = Self.makeServer()
        let (roomID, _) = try await Self.makeRoom(server)
        await #expect(throws: InMemoryServer.error(.notRoomMember)) {
            try await server.device(of: "mallory").drawGacha(RoomRequest(roomId: roomID))
        }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            try await server.drawGacha(RoomRequest(roomId: "missing"))
        }
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            try await server.drawGacha(RoomRequest(roomId: "a/b"))
        }
        #expect(throws: InMemoryServer.error(.unauthenticated)) {
            try server.drawGacha(RoomRequest(roomId: roomID), by: nil)
        }
        #expect(server.rooms[roomID]?.draws.isEmpty == true)
        #expect(server.rooms[roomID]?.room.status == .unlocked)
    }

    /// open は「まだガチャは解禁されていません」・closed は「もう行き先が決まっています」
    @Test
    func rejectsOpenAndClosed() async throws {
        let server = Self.makeServer()
        let (roomID, _) = try await Self.makeRoom(server, ready: ["owner"])
        #expect(server.rooms[roomID]?.room.status == .open)
        await #expect(throws: InMemoryServer.error(.roomNotUnlocked)) {
            try await server.drawGacha(RoomRequest(roomId: roomID))
        }
        server.rooms[roomID]?.room.status = .closed
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            try await server.drawGacha(RoomRequest(roomId: roomID))
        }
        #expect(server.rooms[roomID]?.draws.isEmpty == true)
    }

    /// unlocked と書いてあっても、数え直すと条件を満たさない（参加の直後でトリガーが戻す前）なら断る
    @Test
    func rejectsWhenRecountIsNotUnlocked() async throws {
        let server = Self.makeServer()
        let (roomID, _) = try await Self.makeRoom(server, ready: ["owner", "bob"])
        server.rooms[roomID]?.room.status = .unlocked
        server.rooms[roomID]?.room.readyCount = 3
        await #expect(throws: InMemoryServer.error(.roomNotUnlocked)) {
            try await server.drawGacha(RoomRequest(roomId: roomID))
        }
        #expect(server.rooms[roomID]?.draws.isEmpty == true)
        #expect(server.rooms[roomID]?.room.status == .unlocked)
    }

    /// 強制解禁したルームは、準備OKが 0 人でも回せる（02 の F-32）
    @Test
    func forcedUnlockAllowsDraw() async throws {
        let server = Self.makeServer()
        let (roomID, candidates) = try await Self.makeRoom(server, ready: [])
        try await server.forceUnlock(RoomRequest(roomId: roomID))
        #expect(try await server.drawGacha(RoomRequest(roomId: roomID)).candidateId == candidates[0])
    }

    /// 引き直しの可決の後は、除外した候補は当選せず、記録は引き直しの抽選になる（準備OKの数は見ない）
    @Test
    func rerollExcludesPreviousWinner() async throws {
        let server = Self.makeServer()
        let (roomID, candidates) = try await Self.makeRoom(server, ready: ["owner"])
        server.rooms[roomID]?.room.status = .unlocked
        server.rooms[roomID]?.room.reroll.status = .passed
        server.rooms[roomID]?.room.excludedCandidateIds = [candidates[0]]
        server.rooms[roomID]?.room.winnerCandidateId = candidates[0]
        server.rooms[roomID]?.room.currentDrawId = "old"

        let response = try await server.drawGacha(RoomRequest(roomId: roomID))
        #expect(response.candidateId == candidates[1])
        #expect(response.drawId != "old")
        let draw = try #require(server.rooms[roomID]?.draws[response.drawId])
        #expect(draw.isReroll)
        #expect(draw.weights.keys.sorted() == [candidates[1], candidates[2]])
        #expect(server.rooms[roomID]?.room.winnerCandidateId == candidates[1])
    }

    /// 候補が 0 件・すべて除外したときは「候補がありません」（02 の F-40）
    @Test
    func rejectsWithoutCandidates() async throws {
        let server = Self.makeServer()
        let emptyRoom = try await InMemoryServerUnlockTests.makeRoom(server, ready: ["owner", "bob", "carol"])
        await #expect(throws: InMemoryServer.error(.noCandidates)) {
            try await server.drawGacha(RoomRequest(roomId: emptyRoom))
        }
        #expect(server.rooms[emptyRoom]?.room.status == .unlocked)
    }
}
