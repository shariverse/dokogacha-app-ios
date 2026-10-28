//
//  InMemoryServerInviteTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `inviteLastMembers`（backend の `invite/service.ts` と同じ検証と結果）を確かめる
struct InMemoryServerInviteTests {
    /// `memories` のサーバーで、自分が作った今のルーム（open）
    static func makeServerWithRoom() async throws -> (InMemoryServer, String) {
        let server = InMemoryServer.demo(.memories) { RoomModelTests.now }
        let created = try await server.createRoom(InMemoryServerTests.simpleRoom(name: "年末の旅行"))
        return (server, created.roomId)
    }

    /// 直近の終了したルームの、自分以外のメンバーを招待して人数を返す
    @Test
    func invitesLatestClosedRoomMembers() async throws {
        let (server, roomID) = try await Self.makeServerWithRoom()
        let response = try await server.inviteLastMembers(RoomRequest(roomId: roomID))
        #expect(response == InviteLastMembersResponse(invitedCount: 2))
        let key = InMemoryServer.lastMembersInvitationKey(
            roomID: roomID,
            userID: DemoScenario.myUserID,
            sourceRoomID: "\(DemoScenario.closedRoomIDPrefix)1"
        )
        #expect(server.lastMembersInvitations[key] == ["demo-haruka", "demo-sota"])
    }

    /// 同じ前回のルームからの 2 回目は、送り直さずに同じ人数を返す（その間に参加した人がいても）
    @Test
    func secondCallReturnsSameCount() async throws {
        let (server, roomID) = try await Self.makeServerWithRoom()
        _ = try await server.inviteLastMembers(RoomRequest(roomId: roomID))
        let code = try #require(server.rooms[roomID]?.room.inviteCode)
        _ = try await InMemoryServerTests.join(server, "demo-haruka", code: code)
        #expect(try await server.inviteLastMembers(RoomRequest(roomId: roomID)) == InviteLastMembersResponse(invitedCount: 2))
        #expect(server.lastMembersInvitations.count == 1)
    }

    /// 同じ今のルームからの 2 回目は、新しく印を作らない（backend と同じ「今のルーム × 招待した人 × 前回のルーム」で 1 回）
    @Test
    func sameCurrentRoomSendsOnlyOnce() async throws {
        let (server, roomID) = try await Self.makeServerWithRoom()
        _ = try await server.inviteLastMembers(RoomRequest(roomId: roomID))
        let first = server.lastMembersInvitations
        _ = try await server.inviteLastMembers(RoomRequest(roomId: roomID))
        #expect(server.lastMembersInvitations == first)
    }

    /// 同じ前回のルームのメンバーを、別の今のルームからもう一度招待できる（印は今のルームごと）
    @Test
    func anotherCurrentRoomCanInviteSameMembersAgain() async throws {
        let (server, roomID) = try await Self.makeServerWithRoom()
        _ = try await server.inviteLastMembers(RoomRequest(roomId: roomID))
        let other = try await server.createRoom(InMemoryServerTests.simpleRoom(name: "春のお花見"))
        #expect(try await server.inviteLastMembers(RoomRequest(roomId: other.roomId)) == InviteLastMembersResponse(invitedCount: 2))
        let source = "\(DemoScenario.closedRoomIDPrefix)1"
        let keys = [roomID, other.roomId].map {
            InMemoryServer.lastMembersInvitationKey(roomID: $0, userID: DemoScenario.myUserID, sourceRoomID: source)
        }
        #expect(keys.map { server.lastMembersInvitations[$0] } == [["demo-haruka", "demo-sota"], ["demo-haruka", "demo-sota"]])
    }

    /// 前回のメンバーが全員もう今のルームにいる・終了したルームが無いなら 0
    @Test
    func zeroWithoutInvitees() async throws {
        let (server, roomID) = try await Self.makeServerWithRoom()
        let code = try #require(server.rooms[roomID]?.room.inviteCode)
        _ = try await InMemoryServerTests.join(server, "demo-haruka", code: code)
        _ = try await InMemoryServerTests.join(server, "demo-sota", code: code)
        #expect(try await server.inviteLastMembers(RoomRequest(roomId: roomID)) == InviteLastMembersResponse(invitedCount: 0))

        let empty = InMemoryServer.demo(.oneRoom)
        #expect(try await empty.inviteLastMembers(RoomRequest(roomId: DemoScenario.roomID)) == InviteLastMembersResponse(invitedCount: 0))
        #expect(server.lastMembersInvitations.isEmpty && empty.lastMembersInvitations.isEmpty)
    }

    /// 無いルーム・メンバーでない・行き先が決まったルーム・正しくない ID は断る（backend と同じ理由）
    @Test
    func rejectsInvalidRequests() async throws {
        let server = InMemoryServer.demo(.memories) { RoomModelTests.now }
        await #expect(throws: InMemoryServer.error(.roomNotFound)) {
            _ = try await server.inviteLastMembers(RoomRequest(roomId: "missing"))
        }
        await #expect(throws: InMemoryServer.error(.invalidArgument)) {
            _ = try await server.inviteLastMembers(RoomRequest(roomId: "a/b"))
        }
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            _ = try await server.inviteLastMembers(RoomRequest(roomId: DemoScenario.drawnRoomID))
        }
        #expect(throws: InMemoryServer.error(.notRoomMember)) {
            _ = try server.inviteLastMembers(RoomRequest(roomId: DemoScenario.drawnRoomID), by: "stranger")
        }
    }
}
