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

    /// カバーが出ていなければ、招待リンクのシートはすぐに出る（出していたシートは差し替える）。待たせるシートが無ければ、カバーを閉じても何も出さない
    @Test
    func inviteLinkWithoutCoverOpensSheetImmediately() throws {
        let code = try #require(InviteCode("QW58RT"))
        var presentation = AppPresentation()
        presentation.open(.candidateDetail(roomID: "r", candidateID: "c"))
        presentation.open(.joinByInviteLink(code))
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
        presentation.open(.result(roomID: "r", drawID: "d1"))
        presentation.open(.gacha(roomID: "r"))
        #expect(presentation.pendingFullScreen == .result(roomID: "r", drawID: "d1"))

        presentation.sheetDismissed()
        #expect(presentation.fullScreen == .result(roomID: "r", drawID: "d1"))
    }

    /// 出しているカバーが別のルームのものなら、開いたルームのカバーに替える。カバーを閉じた後は同じルームでも開く
    @Test
    func otherRoomGachaReplacesCover() {
        var presentation = AppPresentation()
        presentation.open(.result(roomID: "r1", drawID: "d1"))
        presentation.open(.gacha(roomID: "r2"))
        #expect(presentation.fullScreen == .gacha(roomID: "r2"))

        var closed = AppPresentation()
        closed.open(.result(roomID: "r", drawID: "d1"))
        closed.fullScreen = nil
        closed.fullScreenDismissed()
        closed.open(.gacha(roomID: "r"))
        #expect(closed.fullScreen == .gacha(roomID: "r"))
    }
}
