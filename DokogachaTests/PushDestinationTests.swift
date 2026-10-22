//
//  PushDestinationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 通知のペイロード（backend の `pushData`）から開く画面を決めることと、前面で届いた通知を出すか（02 の §8・05 の §7）を確かめる
struct PushDestinationTests {
    /// 解禁・抽選結果・引き直しの提案のペイロード（backend の `notifications/logic.test.ts` の `pushData` と同じ形）を読む
    @Test
    func readsPayloadsFromBackend() throws {
        let unlocked = try #require(PushDestination(userInfo: ["type": "unlocked", "roomId": "r1", "target": "room"]))
        #expect(unlocked == PushDestination(kind: .unlocked, roomID: "r1", target: .room))

        let drawn = try #require(PushDestination(userInfo: ["type": "drawn", "roomId": "r1", "target": "result", "drawId": "d1"]))
        #expect(drawn == PushDestination(kind: .drawn, roomID: "r1", target: .result, drawID: "d1"))

        let reroll = try #require(PushDestination(userInfo: [
            "type": "rerollProposed", "roomId": "r1", "target": "result", "drawId": "d1",
            "aps": ["alert": ["body": "ぼぶさんが引き直しを提案しています"]]
        ]))
        #expect(reroll == PushDestination(kind: .rerollProposed, roomID: "r1", target: .result, drawID: "d1"))
    }

    /// roomId が無い・ドキュメントの ID として正しくない通知は開かない
    @Test(arguments: [
        [:],
        ["target": "room"],
        ["roomId": ""],
        ["roomId": "rooms/other"],
        ["roomId": "__x__"]
    ] as [[String: String]])
    func ignoresPayloadWithoutValidRoomID(_ payload: [String: String]) {
        #expect(PushDestination(userInfo: payload) == nil)
    }

    /// roomId が文字列でない通知は開かない
    @Test
    func ignoresNonStringRoomID() {
        #expect(PushDestination(userInfo: ["roomId": 1, "target": "room"]) == nil)
    }

    /// 知らない遷移先・種類はルームを開く。正しくない抽選の ID は使わない
    @Test
    func fallsBackForUnknownValues() throws {
        let destination = try #require(PushDestination(userInfo: ["roomId": "r1", "target": "map", "type": "new", "drawId": "a/b"]))
        #expect(destination == PushDestination(kind: nil, roomID: "r1", target: .room, drawID: nil))
    }

    /// ほかの画面・ほかのルームを出しているときは、前面でもバナーで出す
    @Test
    func showsBannerOutsideTheRoom() {
        let destination = PushDestination(kind: .unlocked, roomID: "r1", target: .room)
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: nil))
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r2", isGachaCover: false)))
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r2", isGachaCover: true)))
        #expect(PushForegroundPolicy.showsBanner(for: nil, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: true)))
    }

    /// そのルームの S-07 では、解禁・抽選結果は出さず（画面が替わる・演出を再生する）、引き直しの提案だけを出す
    @Test(arguments: [
        (PushDestination.Kind.unlocked, false),
        (.drawn, false),
        (.rerollProposed, true)
    ])
    func onRoomScreenShowsOnlyRerollProposal(kind: PushDestination.Kind, shows: Bool) {
        let destination = PushDestination(kind: kind, roomID: "r1", target: kind == .unlocked ? .room : .result)
        #expect(PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: false)) == shows)
    }

    /// そのルームの S-13・S-14 では、どの通知も出さない（演出の上に重ねない・提案は S-14 に出る）
    @Test(arguments: [PushDestination.Kind.unlocked, .drawn, .rerollProposed])
    func onGachaCoverShowsNothing(kind: PushDestination.Kind) {
        let destination = PushDestination(kind: kind, roomID: "r1", target: .result)
        #expect(!PushForegroundPolicy.showsBanner(for: destination, visible: VisibleRoomScreen(roomID: "r1", isGachaCover: true)))
    }
}
