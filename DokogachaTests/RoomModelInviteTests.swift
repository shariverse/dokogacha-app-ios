//
//  RoomModelInviteTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-07 のアバターの並びの招待の「＋」（`RoomModel.inviteAvailability`・`inviteDestination`。02 の §2.4 F-04）を、擬似のサーバーで確かめる。
///
/// - 招待できるのは `open`・`unlocked` で 20 人未満のとき。作成者でなくても招待できる
/// - 満員（20 人）は押せない（招待の画面に渡すルームも無い）。誰かが抜けると、また招待できる
/// - `drawn`・`closed`・ルームが届くまでは入口を出さない
struct RoomModelInviteTests {
    /// ルームが届き、メンバーが `members` 人そろうまで待つ
    static func waitUntilLoaded(_ model: RoomModel, members: Int) async -> Bool {
        await AsyncTestSupport.eventually {
            model.loadState == .loaded && model.members.count == members
        }
    }

    /// 招待できるルームでは、招待の画面にルーム名と招待コードを渡す
    @Test
    func openRoomIsInvitableWithNameAndCode() async throws {
        let server = RoomModelTests.makeServer()
        let model = RoomModelTests.makeModel(server)
        #expect(model.inviteAvailability == .unavailable)
        #expect(model.inviteDestination == nil)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4))

        #expect(model.inviteAvailability == .available)
        let destination = try #require(model.inviteDestination)
        #expect(destination.roomID == DemoScenario.roomID)
        #expect(destination.roomName == "年末の旅行")
        #expect(destination.inviteCode.displayText == "DK7-29Q")
    }

    /// 作成者でないメンバーも招待できる（02 の §2.4 に作成者だけとは無い。S-11 の「招待する」と同じ）
    @Test
    func nonOwnerCanInvite() async {
        let server = RoomModelTests.makeServer()
        let model = RoomModelTests.makeModel(server, userID: "demo-haruka")
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4))

        #expect(!model.isOwner)
        #expect(model.inviteAvailability == .available)
        #expect(model.inviteDestination != nil)
    }

    /// 解禁された（`unlocked`）ルームにも招待できる（参加すると解禁の条件を数え直す。02 の §2.4）
    @Test
    func unlockedRoomIsInvitable() async throws {
        let server = RoomModelTests.makeServer()
        try server.forceUnlock(RoomRequest(roomId: DemoScenario.roomID), by: DemoScenario.myUserID)
        let model = RoomModelTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4))

        #expect(model.room?.status == .unlocked)
        #expect(model.inviteAvailability == .available)
    }

    /// 満員（20 人）では押せず、招待の画面に渡すルームも無い。誰かが抜けて 19 人になると、また招待できる
    @Test
    func fullRoomBecomesInvitableWhenSomeoneLeaves() async throws {
        let server = RoomModelTests.makeServer(.fullRoom)
        let model = RoomModelTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: DomainConstants.Limits.maxMembers))

        #expect(model.inviteAvailability == .full)
        #expect(model.inviteDestination == nil)

        try await server.device(of: "demo-guest-16").leaveRoom(RoomRequest(roomId: DemoScenario.roomID))
        #expect(await AsyncTestSupport.eventually { model.inviteAvailability == .available })
        #expect(model.inviteDestination != nil)
    }

    /// 行き先が決まった（`drawn`）・終了した（`closed`）ルームでは、招待の入口を出さない（招待しても参加できないため）
    @Test(arguments: [RoomStatus.drawn, .closed])
    func decidedRoomHidesInvite(_ status: RoomStatus) async {
        let server = RoomModelTests.makeServer()
        server.rooms[DemoScenario.roomID]?.room.status = status
        let model = RoomModelTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4))

        #expect(model.inviteAvailability == .unavailable)
        #expect(model.inviteDestination == nil)
    }

    /// 招待コードが読めない（壊れた）ルームでは、招待の入口を出さない（招待のしようが無いため）
    @Test
    func roomWithBrokenInviteCodeHidesInvite() async {
        let server = RoomModelTests.makeServer()
        server.rooms[DemoScenario.roomID]?.room.inviteCode = "X"
        let model = RoomModelTests.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4))

        #expect(model.inviteAvailability == .unavailable)
    }

    /// 招待の画面はシートで出す（03 の §1 の S-11・S-12 と同じく、ルームから開くものはシート）
    @Test
    func inviteMembersRouteIsSheet() throws {
        let code = try #require(InviteCode(DemoScenario.inviteCode))
        let route = AppRoute.inviteMembers(InviteDestination(roomID: DemoScenario.roomID, roomName: "年末の旅行", inviteCode: code))
        #expect(route.presentation == .sheet)
    }
}
