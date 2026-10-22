//
//  RoomSheetsUITests.swift
//  DokogachaUITests
//

import XCTest

/// ルーム（S-07）から開くシート（S-11 メンバー一覧・S-12 ルーム設定）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす
final class RoomSheetsUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ほかの人が作ったルーム（S-07）のメンバーから S-11 を開き、「ルームから退出」→ 確認の「退出する」で、
    /// シートが閉じてホームに戻り、そのルームがホームの進行中のルームから消える（F-05）
    @MainActor
    func testLeaveRoomFromMembersReturnsHome() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms"]
        app.launch()

        let card = app.buttons[UITestID.othersRoomCard]
        if !card.waitForExistence(timeout: UITestID.timeout) || !card.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        // ルームパネルのメンバーから S-11 を開く。作成者ではないので「ルームから退出」がある
        let members = app.buttons[UITestID.roomMembers]
        XCTAssertTrue(members.waitForExistence(timeout: UITestID.timeout))
        members.tap()
        let sheet = app.otherElements[UITestID.membersScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.descendants(matching: .any)[UITestID.membersRow("demo-haruka")].waitForExistence(timeout: UITestID.timeout))
        let leave = app.buttons[UITestID.membersLeave]
        XCTAssertTrue(leave.waitForExistence(timeout: UITestID.timeout))
        leave.tap()

        let confirm = app.buttons["退出する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()

        // シートが閉じてホームに戻り、退出したルームが無くなる
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.demoRoomCard].exists)
    }

    /// 作成者がルーム（S-07）のヘッダーの設定から S-12 を開き、投稿数を 3 から 5 に上げて「保存」すると、
    /// シートが閉じて S-07 の「あなたの投稿 n/上限件」の上限が 5 になる（F-03）。今の値より下には減らせない
    @MainActor
    func testRaisePostLimitInRoomSettings() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["あなたの投稿 1/3件 · 共感ブースト"].waitForExistence(timeout: UITestID.timeout))

        app.buttons[UITestID.roomSettings].tap()
        let sheet = app.otherElements[UITestID.roomSettingsScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))

        // 今の値（3）より下には減らせず、何も変えていないので保存できない
        let decrement = sheet.buttons["投稿数を減らす"]
        let increment = sheet.buttons["投稿数を増やす"]
        XCTAssertTrue(increment.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(decrement.isEnabled)
        let save = app.buttons[UITestID.roomSettingsSave]
        XCTAssertFalse(save.isEnabled)

        increment.tap()
        increment.tap()
        XCTAssertTrue(decrement.isEnabled)
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // シートが閉じて、S-07 の上限が 5 になる
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["あなたの投稿 1/5件 · 共感ブースト"].waitForExistence(timeout: UITestID.timeout))
    }
}
