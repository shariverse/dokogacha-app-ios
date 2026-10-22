//
//  AppPresentationNotificationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 通知を開いたときの画面の出し方（02 の §8「通知をタップすると該当ルーム（結果があれば結果画面）を開く」）と、
/// いま出しているルームの画面の判定を確かめる
struct AppPresentationNotificationTests {
    private let unlocked = PushDestination(kind: .unlocked, roomID: "r1", target: .room)
    private let drawn = PushDestination(kind: .drawn, roomID: "r1", target: .result, drawID: "d1")

    /// ホームから開くと、そのルームを積む（drawn なら S-07 が開いたときに S-14 を自動で出す）
    @Test
    func opensRoomFromHome() {
        var presentation = AppPresentation()
        presentation.openNotification(unlocked)
        #expect(presentation.path == [.room(id: "r1")])

        var fromResult = AppPresentation()
        fromResult.openNotification(drawn)
        #expect(fromResult.path == [.room(id: "r1")])
        #expect(fromResult.fullScreen == nil)
    }

    /// ほかの画面を積んでいたら、ホームの上にそのルームだけを積み直し、シートを閉じる
    @Test
    func replacesStackAndClosesSheet() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r2"))
        presentation.open(.addCandidate(roomID: "r2"))
        presentation.open(.members(roomID: "r2"))
        presentation.openNotification(unlocked)
        #expect(presentation.path == [.room(id: "r1")])
        #expect(presentation.sheet == nil)
    }

    /// もうそのルームの S-07 を出していれば、積み直さない。結果を開く通知なら S-14 を開く
    @Test
    func opensResultOnTheSameRoom() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r1"))
        presentation.openNotification(unlocked)
        #expect(presentation.path == [.room(id: "r1")])
        #expect(presentation.fullScreen == nil)

        presentation.openNotification(drawn)
        #expect(presentation.path == [.room(id: "r1")])
        #expect(presentation.fullScreen == .result(roomID: "r1", drawID: "d1"))
    }

    /// そのルームの S-07 の上にシートが出ていたら、シートを閉じ終えてから S-14 を出す
    @Test
    func resultWaitsForSheetOnTheSameRoom() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r1"))
        presentation.open(.candidateDetail(roomID: "r1", candidateID: "c"))
        presentation.openNotification(drawn)
        #expect(presentation.sheet == nil)
        #expect(presentation.pendingFullScreen == .result(roomID: "r1", drawID: "d1"))
        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .result(roomID: "r1", drawID: "d1"))
    }

    /// カバー（S-13・S-14）は閉じない。同じルームなら替えず、ほかのルームならカバーの下で積み直す
    @Test
    func keepsGachaCover() {
        var same = AppPresentation()
        same.open(.room(id: "r1"))
        same.open(.gacha(roomID: "r1"))
        same.openNotification(drawn)
        #expect(same.fullScreen == .gacha(roomID: "r1"))
        #expect(same.path == [.room(id: "r1")])

        var other = AppPresentation()
        other.open(.room(id: "r2"))
        other.open(.result(roomID: "r2", drawID: "d9"))
        other.openNotification(unlocked)
        #expect(other.fullScreen == .result(roomID: "r2", drawID: "d9"))
        #expect(other.path == [.room(id: "r1")])
    }

    /// 結果を開く通知でも、抽選の ID が無ければ（そのルームを出していても）S-14 は開かない
    @Test
    func resultWithoutDrawIDOpensRoomOnly() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r1"))
        presentation.openNotification(PushDestination(kind: .rerollProposed, roomID: "r1", target: .result))
        #expect(presentation.fullScreen == nil)
        #expect(presentation.path == [.room(id: "r1")])
    }

    /// いま出しているルームの画面: カバーならそのルーム、シートが無ければ積みのいちばん上の S-07、それ以外は nil
    @Test
    func visibleRoomScreen() {
        var presentation = AppPresentation()
        #expect(presentation.visibleRoomScreen == nil)
        presentation.open(.room(id: "r1"))
        #expect(presentation.visibleRoomScreen == VisibleRoomScreen(roomID: "r1", isGachaCover: false))
        presentation.open(.members(roomID: "r1"))
        #expect(presentation.visibleRoomScreen == nil)
        presentation.sheet = nil
        presentation.open(.addCandidate(roomID: "r1"))
        #expect(presentation.visibleRoomScreen == nil)
        presentation.open(.gacha(roomID: "r1"))
        #expect(presentation.visibleRoomScreen == VisibleRoomScreen(roomID: "r1", isGachaCover: true))
    }
}
