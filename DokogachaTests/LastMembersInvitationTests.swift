//
//  LastMembersInvitationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-04 の「前回のメンバー（{前回ルーム名}・N人）を招待」に出す前回のルームと人数（02 の §2.4）を確かめる。
/// 招待する人の規則は backend の `invite/logic.test.ts` と同じケース
struct LastMembersInvitationTests {
    /// `memories` のルーム（終了したルーム 6 つと、行き先が決まったルーム 2 つ）
    private static func demoRooms() -> [Identified<Room>] {
        InMemoryServer.demo(.memories) { RoomModelTests.now }.rooms.map { Identified(id: $0.key, value: $0.value.room) }
    }

    /// 終了の日時がいちばん新しい終了したルームを選び、自分以外の人数を数える（行き先が決まったルームは選ばない）
    @Test
    func picksLatestClosedRoom() throws {
        let me = DemoScenario.myUserID
        let invitation = try #require(LastMembersInvitation.make(closedRooms: Self.demoRooms(), currentMemberIDs: [me], userID: me))
        #expect(invitation.sourceRoomName == "夏の日帰り")
        #expect(invitation.sourceRoomID == "\(DemoScenario.closedRoomIDPrefix)1")
        #expect(invitation.inviteeIDs == ["demo-haruka", "demo-sota"])
        #expect(invitation.count == 2)
    }

    /// 今のルームにもういる人は数えない。全員がもういれば nil（ボタンを出さない）
    @Test
    func skipsCurrentMembers() throws {
        let rooms = Self.demoRooms()
        let me = DemoScenario.myUserID
        let one = try #require(LastMembersInvitation.make(closedRooms: rooms, currentMemberIDs: [me, "demo-sota"], userID: me))
        #expect(one.inviteeIDs == ["demo-haruka"])
        #expect(
            LastMembersInvitation.make(closedRooms: rooms, currentMemberIDs: [me, "demo-sota", "demo-haruka"], userID: me) == nil
        )
    }

    /// 終了したルームが無い・自分が入っていない終了したルームしか無ければ nil
    @Test
    func nilWithoutClosedRoom() {
        let rooms = Self.demoRooms()
        #expect(LastMembersInvitation.make(closedRooms: [], currentMemberIDs: [], userID: DemoScenario.myUserID) == nil)
        #expect(LastMembersInvitation.make(closedRooms: rooms, currentMemberIDs: [], userID: "demo-mio") == nil)
    }

    /// 招待する人のケース（前回のメンバー・今のメンバー・招待する人）
    struct InviteesCase: Sendable {
        let previous: [String]
        let current: [String]
        let expected: [String]
    }

    nonisolated static let inviteesCases = [
        InviteesCase(previous: ["me", "a", "b", "c"], current: ["me", "b"], expected: ["a", "c"]),
        InviteesCase(previous: ["a", "me", "a", "b"], current: ["me"], expected: ["a", "b"]),
        InviteesCase(previous: ["me"], current: ["me"], expected: []),
        InviteesCase(previous: ["me", "a"], current: ["me", "a"], expected: [])
    ]

    /// 前回のメンバーから自分と今のメンバーを外し、参加の順を保つ・同じ人は 1 回だけ（backend と同じケース）
    @Test(arguments: inviteesCases)
    func invitees(_ testCase: InviteesCase) {
        let result = LastMembersInvitation.invitees(previousMemberIDs: testCase.previous, currentMemberIDs: testCase.current, userID: "me")
        #expect(result == testCase.expected)
    }
}
