//
//  InviteLastMembersUITests.swift
//  DokogachaUITests
//

import XCTest

/// 前回のメンバーへの招待（03 の S-04 の 4・02 の §2.4・§8）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす
final class InviteLastMembersUITests: XCTestCase {
    /// 招待の通知のペイロード（backend の `pushData` と同じ形。`joinable` の参加できるルームの招待コード）
    private static let invitedPayload =
        #"{"type":"invited","roomId":"demo-room-joinable","target":"join","inviteCode":"QW58RT"}"#

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 終了したルームがある人がルームを作ると、S-04 に「前回のメンバー（夏の日帰り・2人）を招待」が出て、
    /// 押すとトースト「前回のメンバー2人に招待を送りました」が出て、もう押せなくなる
    @MainActor
    func testInviteLastMembersFromInviteScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "memories"]
        app.launch()

        let createRoom = app.buttons[UITestID.createRoomButton]
        XCTAssertTrue(createRoom.waitForExistence(timeout: UITestID.timeout))
        createRoom.tap()
        let name = app.textFields[UITestID.roomNameField]
        XCTAssertTrue(name.waitForExistence(timeout: UITestID.timeout))
        name.tap()
        name.typeText("年末の旅行")
        app.buttons[UITestID.createRoomSubmit].tap()

        XCTAssertTrue(app.otherElements[UITestID.inviteScreen].waitForExistence(timeout: UITestID.timeout))
        let button = app.buttons[UITestID.inviteLastMembersButton]
        XCTAssertTrue(button.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(button.label, "前回のメンバー（夏の日帰り・2人）を招待")
        XCTAssertTrue(button.isEnabled)
        button.tap()

        XCTAssertTrue(app.staticTexts["前回のメンバー2人に招待を送りました"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(button.isEnabled)
    }

    /// 前回のメンバーへの招待の通知を開くと、そのルームの S-06 参加確認が開く（招待リンクと同じ道）
    @MainActor
    func testOpeningInvitationNotificationOpensJoinConfirm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "joinable", "-open-notification", Self.invitedPayload]
        app.launch()

        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.joinConfirmJoin].waitForExistence(timeout: UITestID.timeout))
    }
}
