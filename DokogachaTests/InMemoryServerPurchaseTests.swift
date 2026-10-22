//
//  InMemoryServerPurchaseTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `verifyPurchase`（backend の `purchase/service.ts`。Emulator のテスト `test/emulator/purchase.test.ts` と同じ観点）
struct InMemoryServerPurchaseTests {
    /// 形だけの署名付きトランザクション（擬似のサーバーは署名を確かめない）
    nonisolated private static let signed = VerifyPurchaseRequest(signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJ0ZXN0Ijp0cnVlfQ.c2ln")

    /// 参加の日時が 1 分ずつずれる擬似のサーバー
    private static func makeServer() -> (InMemoryServer, TestClock) {
        let clock = TestClock(Date(timeIntervalSince1970: 1_760_000_000))
        var counter = 0
        var draws = 0
        let server = InMemoryServer(
            clock: clock.read,
            // ルームごとに別の招待コードになるよう、乱数を順に進める
            randomIndex: { upperBound in
                draws += 1
                return draws % upperBound
            },
            makeID: {
                counter += 1
                return "id-\(counter)"
            },
            signedInUserID: "owner"
        )
        return (server, clock)
    }

    /// 表示名を登録したユーザーを作る
    private static func addUser(_ server: InMemoryServer, _ userID: String, adFree: Bool = false) throws {
        _ = try server.saveProfile(SaveProfileRequest(displayName: userID), by: userID)
        server.users[userID]?.adFree = adFree
    }

    /// `owner` が作ったルームに `joiners` を 1 分ずつ遅らせて参加させる
    private static func makeRoom(
        _ server: InMemoryServer,
        _ clock: TestClock,
        owner: String,
        joiners: [String]
    ) throws -> String {
        let room = try server.createRoom(InMemoryServerTests.simpleRoom(name: "年末の旅行"), by: owner)
        for userID in joiners {
            clock.advance(by: 60)
            _ = try server.joinRoom(JoinRoomRequest(inviteCode: room.inviteCode), by: userID)
        }
        return room.roomId
    }

    @Test
    func verifyPurchaseSetsAdFreeAndSponsorOfJoinedRooms() throws {
        let (server, clock) = Self.makeServer()
        try Self.addUser(server, "alice")
        try Self.addUser(server, "bob")
        let joined = try Self.makeRoom(server, clock, owner: "alice", joiners: ["bob"])
        server.rooms[joined]?.room.status = .closed
        let others = try Self.makeRoom(server, clock, owner: "alice", joiners: [])

        #expect(try server.verifyPurchase(Self.signed, by: "bob") == VerifyPurchaseResponse(adFree: true))
        #expect(server.users["bob"]?.adFree == true)
        #expect(server.rooms[joined]?.room.adFreeSponsor == AdFreeSponsor(uid: "bob", displayName: "bob"))
        #expect(server.rooms[others]?.room.adFreeSponsor == nil)
        #expect(server.users["alice"]?.adFree == false)
    }

    /// 先に参加した購入者は変えず、後から参加した購入者は購入した人に替える（最初に参加した購入者）
    @Test
    func verifyPurchaseKeepsEarlierSponsorAndReplacesLaterOne() throws {
        let (server, clock) = Self.makeServer()
        for userID in ["alice", "bob"] {
            try Self.addUser(server, userID)
        }
        try Self.addUser(server, "carol", adFree: true)
        try Self.addUser(server, "erin", adFree: true)
        let kept = try Self.makeRoom(server, clock, owner: "erin", joiners: ["bob"])
        let replaced = try Self.makeRoom(server, clock, owner: "alice", joiners: ["bob", "carol"])
        #expect(server.rooms[replaced]?.room.adFreeSponsor?.uid == "carol")

        _ = try server.verifyPurchase(Self.signed, by: "bob")
        #expect(server.rooms[kept]?.room.adFreeSponsor?.uid == "erin")
        #expect(server.rooms[replaced]?.room.adFreeSponsor == AdFreeSponsor(uid: "bob", displayName: "bob"))
        // 何度呼んでも同じ
        _ = try server.verifyPurchase(Self.signed, by: "bob")
        #expect(server.rooms[replaced]?.room.adFreeSponsor?.uid == "bob")
    }

    /// 購入した後に参加したルームにも購入者が入る（joinRoom との整合）
    @Test
    func joinAfterPurchaseSetsSponsor() throws {
        let (server, clock) = Self.makeServer()
        try Self.addUser(server, "alice")
        try Self.addUser(server, "bob")
        _ = try server.verifyPurchase(Self.signed, by: "bob")
        let room = try Self.makeRoom(server, clock, owner: "alice", joiners: ["bob"])
        #expect(server.rooms[room]?.room.adFreeSponsor?.uid == "bob")
    }

    @Test
    func verifyPurchaseRejectsMissingProfileAndMalformedInput() throws {
        let (server, _) = Self.makeServer()
        #expect(throws: InMemoryServer.error(.profileRequired)) {
            try server.verifyPurchase(Self.signed, by: "nobody")
        }
        try Self.addUser(server, "bob")
        for value in ["", "abc", "a.b", "a.b.c.d", ".b.c", "a..c", "a+b.c.d", String(repeating: "a", count: 16 * 1_024) + ".b.c"] {
            #expect(throws: InMemoryServer.error(.invalidArgument)) {
                try server.verifyPurchase(VerifyPurchaseRequest(signedTransaction: value), by: "bob")
            }
        }
        #expect(server.users["bob"]?.adFree == false)
        #expect(throws: InMemoryServer.error(.unauthenticated)) {
            try server.verifyPurchase(Self.signed, by: nil)
        }
    }

    /// デモの `ad-free-room` は、はるかが購入者のルーム（S-07 の UI テスト・撮影用）
    @Test
    func adFreeRoomScenarioHasSponsor() {
        let server = InMemoryServer.demo(.adFreeRoom)
        #expect(server.users[DemoScenario.adFreeSponsorUserID]?.adFree == true)
        #expect(server.users[DemoScenario.myUserID]?.adFree == false)
        #expect(server.rooms[DemoScenario.roomID]?.room.adFreeSponsor == AdFreeSponsor(uid: "demo-haruka", displayName: "はるか"))
        #expect(server.rooms[DemoScenario.roomID]?.candidates.count == 3)
    }
}
