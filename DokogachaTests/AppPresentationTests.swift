//
//  AppPresentationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 画面の行き先の開き方（シートの上にフルスクリーンカバーを重ねない・カバーを出している間はシートを待たせる）を確かめる
struct AppPresentationTests {
    /// 表示形式どおりに積む・シート・カバーで出す
    @Test
    func opensByPresentation() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r"))
        presentation.open(.members(roomID: "r"))
        #expect(presentation.path == [.room(id: "r")])
        #expect(presentation.sheet == .members(roomID: "r"))
        presentation.sheet = nil
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        #expect(presentation.pendingFullScreen == nil)
    }

    /// シートが出ている間にカバーを開くと、先にシートを閉じ、閉じ終えてからカバーを出す（ほかの人が回したときの再生を捨てない）
    @Test
    func coverWaitsForSheetToClose() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r"))
        presentation.open(.candidateDetail(roomID: "r", candidateID: "c"))
        presentation.sheetAppeared()
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.sheet == nil)
        #expect(presentation.fullScreen == nil)
        #expect(presentation.pendingFullScreen == .gacha(roomID: "r"))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        #expect(presentation.pendingFullScreen == nil)
        #expect(presentation.path == [.room(id: "r")])
    }

    /// 待たせているカバーが無ければ、シートを閉じても何も出さない
    @Test
    func sheetDismissWithoutPendingDoesNothing() {
        var presentation = AppPresentation()
        presentation.open(.roomSettings(roomID: "r"))
        presentation.sheet = nil
        presentation.sheetDismissed()
        #expect(presentation.fullScreen == nil)
    }

    /// S-13 の演出中に招待リンクが届いても、カバーを閉じずに待たせ、ユーザーがカバーを閉じてから S-05・S-06 のシートを出す
    @Test
    func inviteLinkWaitsForGachaCoverToClose() throws {
        let code = try #require(InviteCode("QW58RT"))
        var presentation = AppPresentation()
        presentation.open(.room(id: "r"))
        presentation.open(.gacha(roomID: "r"))
        presentation.open(.joinByInviteLink(code))
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        #expect(presentation.sheet == nil)
        #expect(presentation.pendingSheet == .joinByInviteLink(code))

        // ユーザーがカバーを閉じた（`fullScreenCover` のバインディングが nil にしてから onDismiss）
        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        #expect(presentation.sheet == .joinByInviteLink(code))
        #expect(presentation.pendingSheet == nil)
        #expect(presentation.path == [.room(id: "r")])
    }

    /// S-14 の結果を出している間に招待リンクが届いても、カバーを閉じずに待たせる
    @Test
    func inviteLinkWaitsForResultCoverToClose() throws {
        let code = try #require(InviteCode("QW58RT"))
        var presentation = AppPresentation()
        presentation.open(.result(roomID: "r", drawID: "d"))
        presentation.open(.joinByInviteLink(code))
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d"))
        #expect(presentation.sheet == nil)

        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        #expect(presentation.sheet == .joinByInviteLink(code))
    }

    /// シートを閉じてカバーを出す途中に招待リンクが届いたら、カバーを出し、カバーを閉じてからシートを出す（カバーの再生を捨てない）
    @Test
    func inviteLinkWhileCoverWaitsForSheetToClose() throws {
        let code = try #require(InviteCode("QW58RT"))
        var presentation = AppPresentation()
        presentation.open(.members(roomID: "r"))
        presentation.sheetAppeared()
        presentation.open(.gacha(roomID: "r"))
        presentation.open(.joinByInviteLink(code))
        #expect(presentation.sheet == nil)
        #expect(presentation.pendingFullScreen == .gacha(roomID: "r"))
        #expect(presentation.pendingSheet == .joinByInviteLink(code))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        #expect(presentation.sheet == nil)

        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        #expect(presentation.sheet == .joinByInviteLink(code))
    }

    /// カバーもシートも出ていなければ、招待リンクのシートはすぐに出る。ほかのシート（編集の途中の S-12 など）を出していたら替えず、
    /// 閉じ終えてから出す（PR #70 の持ち越し）。待たせるシートが無ければ、カバーを閉じても何も出さない
    @Test
    func inviteLinkWithoutCoverOpensSheetImmediately() throws {
        let code = try #require(InviteCode("QW58RT"))
        var empty = AppPresentation()
        empty.open(.joinByInviteLink(code))
        #expect(empty.sheet == .joinByInviteLink(code))
        #expect(empty.pendingSheet == nil)

        var presentation = AppPresentation()
        presentation.open(.roomSettings(roomID: "r"))
        presentation.sheetAppeared()
        presentation.open(.joinByInviteLink(code))
        #expect(presentation.sheet == .roomSettings(roomID: "r"))
        #expect(presentation.pendingSheet == .joinByInviteLink(code))
        presentation.sheet = nil
        presentation.sheetDismissed()
        #expect(presentation.sheet == .joinByInviteLink(code))
        #expect(presentation.pendingSheet == nil)

        var covered = AppPresentation()
        covered.open(.gacha(roomID: "r"))
        covered.fullScreen = nil
        covered.fullScreenDismissed()
        #expect(covered.sheet == nil)
    }

    /// S-14 のカバーの中の S-13 で回した（ほかの人が回した）とき、下の S-07 が同じルームの S-13 を開いても、カバーを替えない（出し直して演出を止めない）
    @Test
    func sameRoomGachaDoesNotReplaceResultCover() {
        var presentation = AppPresentation()
        presentation.open(.room(id: "r"))
        presentation.open(.result(roomID: "r", drawID: "d1"))
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d1"))
        presentation.open(.result(roomID: "r", drawID: "d2"))
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d1"))

        var gacha = AppPresentation()
        gacha.open(.gacha(roomID: "r"))
        gacha.open(.result(roomID: "r", drawID: "d1"))
        gacha.open(.gacha(roomID: "r"))
        #expect(gacha.fullScreen == .gacha(roomID: "r"))
        #expect(gacha.pendingFullScreen == nil)
    }

    /// シートを閉じてから出す待ちのカバーが同じルームのものなら、同じルームの S-13・S-14 を開いても待ちのカバーを替えない
    @Test
    func sameRoomGachaDoesNotReplacePendingCover() {
        var presentation = AppPresentation()
        presentation.open(.members(roomID: "r"))
        presentation.sheetAppeared()
        presentation.open(.result(roomID: "r", drawID: "d1"))
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.pendingFullScreen == .result(roomID: "r", drawID: "d1"))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d1"))
    }

    /// 出しているカバーが別のルームのものでも替えず、閉じ終えてから開いたルームのカバーを出す
    /// （通知で積み直したカバーの下の S-07 が S-14 を開いても、出している演出を止めない。PR #80 の持ち越し）。カバーを閉じた後は同じルームでも開く
    @Test
    func otherRoomCoverWaitsForCurrentCover() {
        var presentation = AppPresentation()
        presentation.open(.result(roomID: "r1", drawID: "d1"))
        presentation.open(.gacha(roomID: "r2"))
        #expect(presentation.fullScreen == .result(roomID: "r1", drawID: "d1"))
        #expect(presentation.pendingFullScreen == .gacha(roomID: "r2"))
        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        #expect(presentation.fullScreen == .gacha(roomID: "r2"))
        #expect(presentation.pendingFullScreen == nil)

        var closed = AppPresentation()
        closed.open(.result(roomID: "r", drawID: "d1"))
        closed.fullScreen = nil
        closed.fullScreenDismissed()
        closed.open(.gacha(roomID: "r"))
        #expect(closed.fullScreen == .gacha(roomID: "r"))
    }

    /// コードからシートを閉じたら、閉じ終えるまでカバーを出さずに待たせる（閉じている途中のシートの上にカバーを出せない。PR #72 の持ち越し）
    @Test
    func coverWaitsForSheetClosedByCode() {
        var presentation = AppPresentation()
        presentation.open(.joinByCode)
        presentation.sheetAppeared()
        // 参加したのでシートを閉じ、ルームを積む。ルームが `drawn` なので、S-07 がすぐに S-14 を開く
        presentation.closeSheet()
        presentation.open(.room(id: "r"))
        presentation.open(.result(roomID: "r", drawID: "d"))
        #expect(presentation.sheet == nil)
        #expect(presentation.fullScreen == nil)
        #expect(presentation.pendingFullScreen == .result(roomID: "r", drawID: "d"))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d"))
        #expect(!presentation.isClosingSheet)
    }

    /// 画面に出る前に閉じたシートは、閉じ終えるのを待たない（`onDismiss` が呼ばれず、カバーが出ないままにならないように）
    @Test
    func sheetClosedBeforeAppearingDoesNotBlockCovers() {
        var presentation = AppPresentation()
        presentation.open(.members(roomID: "r"))
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        #expect(presentation.pendingFullScreen == nil)
        #expect(!presentation.isClosingSheet)

        var closed = AppPresentation()
        closed.open(.members(roomID: "r"))
        closed.closeSheet()
        closed.open(.gacha(roomID: "r"))
        #expect(closed.fullScreen == .gacha(roomID: "r"))
    }

    /// カバーを開くために招待リンクのシートを閉じたら、カバーを閉じた後に出し直す（招待コードを失わない。PR #70 の持ち越し）
    @Test
    func inviteLinkSheetReturnsAfterCover() throws {
        let code = try #require(InviteCode("QW58RT"))
        var presentation = AppPresentation()
        presentation.open(.room(id: "r"))
        presentation.open(.joinByInviteLink(code))
        presentation.sheetAppeared()
        // ほかの人が回したので、S-07 が S-13 を開く
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.sheet == nil)
        #expect(presentation.pendingSheet == .joinByInviteLink(code))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .gacha(roomID: "r"))
        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        #expect(presentation.sheet == .joinByInviteLink(code))
    }

    /// シートが無いときにカバーを直接出したら、古い待ちのカバーを捨てる（後でシートを閉じたときに戻されない。PR #76 の持ち越し）
    @Test
    func directCoverDropsStalePending() {
        var presentation = AppPresentation()
        presentation.open(.members(roomID: "r1"))
        presentation.sheetAppeared()
        presentation.open(.gacha(roomID: "r1"))
        #expect(presentation.pendingFullScreen == .gacha(roomID: "r1"))
        presentation.sheetDismissed()
        presentation.fullScreen = nil
        presentation.fullScreenDismissed()
        presentation.open(.result(roomID: "r2", drawID: "d"))
        #expect(presentation.fullScreen == .result(roomID: "r2", drawID: "d"))
        #expect(presentation.pendingFullScreen == nil)
    }
}
