//
//  AppPresentationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 画面の行き先の開き方（シートの上にフルスクリーンカバーを重ねない）を確かめる
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
}
