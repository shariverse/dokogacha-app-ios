//
//  PushDestinationRoomEndedTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 作成者がルームを途中で終了した通知（Discussion #155 の Q5）を開いたときの行き先と、前面での出し方を確かめる
/// （ペイロードは backend の `notifications/logic.test.ts` の `pushData` と同じ形）
struct PushDestinationRoomEndedTests {
    /// 途中の終了の通知は、終了したルーム（S-07）を開く
    @Test
    func readsRoomEndedPayload() throws {
        let destination = try #require(PushDestination(userInfo: ["type": "roomEnded", "roomId": "r1", "target": "room"]))
        #expect(destination == PushDestination(kind: .roomEnded, roomID: "r1", target: .room))
        #expect(PushDestination.Kind.roomEnded.rawValue == "roomEnded")
    }

    /// そのルームの S-07 を出していても出す（閲覧のみに替わるだけで、誰が終了したかは画面に出ない）。S-13・S-14 のカバーの上には出さない
    @Test
    func roomEndedShownOnRoomScreenButNotOverGachaCover() {
        let destination = PushDestination(kind: .roomEnded, roomID: "r1", target: .room)
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: false)))
        #expect(!PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: true)))
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: nil))
    }
}
