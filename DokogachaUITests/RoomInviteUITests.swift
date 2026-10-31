//
//  RoomInviteUITests.swift
//  DokogachaUITests
//

import XCTest

/// ルーム（S-07）のアバターの並びの招待の「＋」から招待（S-04）をシートで開く UI テスト（02 の §2.4 F-04）。
/// メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす。
///
/// - `crowded-room`: デモのルーム（年末の旅行・招待コード `DK7-29Q`）に 10 人。アバターは 6 人＋「+4」＋「＋」
/// - `full-room`: 同じルームが満員（20 人）
/// - `drawn-rooms`: 自分が作った行き先が決まった（`drawn`）ルーム（週末のランチ）がある
final class RoomInviteUITests: XCTestCase {
    /// `drawn-rooms` の自分が作ったルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.drawnRoomID)`）
    private static let myDrawnRoomCard = "home.room.demo-room-drawn-mine"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 「＋」を押すと、招待コードと「招待リンクを送る」のシートが開く（作った直後の「ルームへ進む」は無い）。閉じるとルームに戻り、
    /// 「＋」の横のアバターを押すと、これまでどおりメンバー一覧（S-11）が開く（「＋」を重ねてもメンバーのボタンを潰さない）
    @MainActor
    func testPlusOpensInviteSheetAndAvatarsStillOpenMembers() throws {
        let app = launchIntoDemoRoom(scenario: "crowded-room")

        // 10 人のルーム（6 人＋「+4」）の並びの後に「＋」がある
        XCTAssertTrue(app.buttons[UITestID.roomMembers].waitForValue("10人"))
        let invite = app.buttons[UITestID.roomInvite]
        XCTAssertTrue(invite.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(invite.label, "メンバーを招待")
        invite.tap()

        let sheet = app.otherElements[UITestID.inviteScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.staticTexts["メンバーを招待"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.staticTexts["年末の旅行"].exists)
        let code = sheet.buttons[UITestID.inviteCode]
        XCTAssertTrue(code.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(code.label.contains("DK7-29Q"), code.label)
        XCTAssertTrue(sheet.buttons[UITestID.inviteShare].exists)
        XCTAssertFalse(sheet.buttons[UITestID.openRoomButton].exists)
        XCTAssertFalse(sheet.staticTexts["ルームを作成しました"].exists)

        app.buttons[UITestID.inviteClose].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].exists)

        let members = app.buttons[UITestID.roomMembers]
        XCTAssertTrue(members.waitForExistence(timeout: UITestID.timeout))
        members.tap()
        XCTAssertTrue(app.otherElements[UITestID.membersScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.membersInvite].waitForEnabled())
    }

    /// 満員（20 人）のルームでは「＋」が押せない「満員」の表示になり、押しても招待のシートは開かない。
    /// メンバー一覧（S-11）の「招待する」も押せない（招待しても参加できないため）
    @MainActor
    func testFullRoomShowsFullAndCannotInvite() throws {
        let app = launchIntoDemoRoom(scenario: "full-room")

        let full = app.descendants(matching: .any)[UITestID.roomInvite]
        XCTAssertTrue(full.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(full.label, "満員のため招待できません")
        XCTAssertFalse(app.buttons[UITestID.roomInvite].exists)
        full.tap()
        XCTAssertFalse(app.otherElements[UITestID.inviteScreen].waitForExistence(timeout: 2))

        app.buttons[UITestID.roomMembers].tap()
        XCTAssertTrue(app.otherElements[UITestID.membersScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["20人 · 最大20人"].waitForExistence(timeout: UITestID.timeout))
        let membersInvite = app.buttons[UITestID.membersInvite]
        XCTAssertTrue(membersInvite.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(membersInvite.isEnabled)
    }

    /// 行き先が決まった（`drawn`）ルームでは「＋」を出さない（招待しても参加できないため）
    @MainActor
    func testDecidedRoomHidesInvite() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "drawn-rooms"]
        app.launch()

        let card = app.buttons[Self.myDrawnRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        // 行き先が決まったルームを開くと S-14 が出るので、戻って S-07 を見る
        let result = app.otherElements[UITestID.resultScreen]
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout))
        result.buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomMembers].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.descendants(matching: .any)[UITestID.roomInvite].exists)
    }

    /// デモのルーム（年末の旅行）を開く
    @MainActor
    private func launchIntoDemoRoom(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", scenario]
        app.launch()
        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        return app
    }
}
