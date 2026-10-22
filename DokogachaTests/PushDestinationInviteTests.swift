//
//  PushDestinationInviteTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 前回のメンバーへの招待・新しい候補のまとめの通知（02 の §8）を開いたときの行き先を確かめる
/// （ペイロードは backend の `notifications/logic.test.ts` の `pushData` と同じ形）
struct PushDestinationInviteTests {
    /// 招待の通知は招待コードで参加確認（S-06）を開く
    @Test
    func readsInvitationPayload() throws {
        let destination = try #require(
            PushDestination(userInfo: ["type": "invited", "roomId": "r1", "target": "join", "inviteCode": "DK729Q"])
        )
        #expect(destination == PushDestination(kind: .invited, roomID: "r1", target: .join, inviteCode: InviteCode("DK729Q")))
    }

    /// 招待の通知に招待コードが無い・正しくなければ開かない（招待された人はルームを読めないので、ルームも開けない）
    @Test(arguments: [
        ["type": "invited", "roomId": "r1", "target": "join"],
        ["type": "invited", "roomId": "r1", "target": "join", "inviteCode": "OOOOOO"]
    ])
    func ignoresInvitationWithoutCode(_ payload: [String: String]) {
        #expect(PushDestination(userInfo: payload) == nil)
    }

    /// まとめの通知はルームを開く。参加確認でない通知の招待コードは使わない
    @Test
    func readsNewCandidatesPayload() throws {
        let destination = try #require(
            PushDestination(userInfo: ["type": "newCandidates", "roomId": "r1", "target": "room", "inviteCode": "DK729Q"])
        )
        #expect(destination == PushDestination(kind: .newCandidates, roomID: "r1", target: .room))
    }

    /// そのルームの S-07 を出しているときは、まとめの通知を出さない（一覧に候補が増えて見える）
    @Test
    func newCandidatesHiddenOnRoomScreen() {
        let destination = PushDestination(kind: .newCandidates, roomID: "r1", target: .room)
        #expect(!PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: false)))
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r2", isGachaCover: false)))
    }

    /// 招待の通知を開くと、招待リンクと同じく招待コードを覚え（S-05・S-06 を開く）、ルームの行き先には入れない
    @Test
    func routerOpensJoinFlowForInvitation() throws {
        let router = DeepLinkRouter()
        let code = try #require(InviteCode("DK729Q"))
        router.handle(PushDestination(kind: .invited, roomID: "r1", target: .join, inviteCode: code))
        #expect(router.pendingNotification == nil)
        #expect(router.takePendingInviteCode() == code)

        let room = PushDestination(kind: .newCandidates, roomID: "r1", target: .room)
        router.handle(room)
        #expect(router.pendingInviteCode == nil)
        #expect(router.takePendingNotification() == room)
    }
}
