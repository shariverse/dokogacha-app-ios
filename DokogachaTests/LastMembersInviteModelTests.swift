//
//  LastMembersInviteModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-04 の「前回のメンバー（{前回ルーム名}・N人）を招待」（`LastMembersInviteModel`）を擬似のサーバーで確かめる
struct LastMembersInviteModelTests {
    struct Fixture {
        let server: InMemoryServer
        let roomID: String
        let toasts: DGToastCenter
        let model: LastMembersInviteModel
    }

    static func makeFixture(_ scenario: DemoScenario = .memories) async throws -> Fixture {
        let server = InMemoryServer.demo(scenario) { RoomModelTests.now }
        let created = try await server.createRoom(InMemoryServerTests.simpleRoom(name: "年末の旅行"))
        let toasts = HomeModelTests.makeToasts()
        let model = LastMembersInviteModel(
            roomID: created.roomId,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts,
            resubscribeDelay: HomeModelTests.immediateResubscribe
        )
        return Fixture(server: server, roomID: created.roomId, toasts: toasts, model: model)
    }

    /// 終了したルームが届くと、前回のルームの名前と人数を出す（届くまではボタンを出さない）
    @Test
    func showsLatestClosedRoom() async throws {
        let fixture = try await Self.makeFixture()
        #expect(fixture.model.invitation == nil)
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { fixture.model.invitation != nil })
        #expect(fixture.model.invitation?.sourceRoomName == "夏の日帰り")
        #expect(fixture.model.invitation?.count == 2)
        #expect(fixture.model.canInvite)
    }

    /// 前回のメンバーが今のルームに参加すると、人数が減る（全員参加したらボタンを出さない）
    @Test
    func countFollowsCurrentMembers() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.invitation?.count == 2 })

        let code = try #require(fixture.server.rooms[fixture.roomID]?.room.inviteCode)
        _ = try await InMemoryServerTests.join(fixture.server, "demo-haruka", code: code)
        #expect(await AsyncTestSupport.eventually { fixture.model.invitation?.count == 1 })
        _ = try await InMemoryServerTests.join(fixture.server, "demo-sota", code: code)
        #expect(await AsyncTestSupport.eventually { fixture.model.invitation == nil })
    }

    /// 終了したルームが無ければボタンを出さない
    @Test
    func hiddenWithoutClosedRoom() async throws {
        let fixture = try await Self.makeFixture(.empty)
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.closedRooms != nil })
        #expect(fixture.model.invitation == nil)
        #expect(!fixture.model.canInvite)
    }

    /// 押すとトースト「前回のメンバーN人に招待を送りました」を出し、その後は押せない
    @Test
    func invitingShowsToastAndDisables() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.canInvite })

        await fixture.model.invite()
        #expect(fixture.toasts.current?.text == "前回のメンバー2人に招待を送りました")
        #expect(fixture.model.hasInvited)
        #expect(!fixture.model.canInvite)
        #expect(fixture.server.lastMembersInvitations.count == 1)
    }

    /// サーバーで断られたら文言のトーストを出し、もう一度押せる
    @Test
    func failureShowsToastAndAllowsRetry() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.canInvite })

        fixture.server.rooms[fixture.roomID]?.room.status = .drawn
        await fixture.model.invite()
        #expect(fixture.toasts.current?.text == InMemoryServer.error(.roomAlreadyDecided).message)
        #expect(!fixture.model.hasInvited)
        #expect(fixture.model.canInvite)
    }
}
