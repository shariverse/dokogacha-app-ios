//
//  DeepLinkUITests.swift
//  DokogachaUITests
//

import XCTest

/// 招待リンク（Universal Links。タスク 34）で開いたときの UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす。
///
/// Simulator では Universal Links でアプリを開けない（AASA を取りに行けない）ので、起動引数 `-open-url <URL>` で
/// 起動の直後に招待リンクを開いたことにする（アプリは `onOpenURL` と同じ `DeepLinkRouter.handle` に渡す）
final class DeepLinkUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 表示名を登録済みなら、招待リンクで開くと S-06 参加確認がそのルームで出て、「参加する」でルーム画面が開く（02 の §2.4）
    @MainActor
    func testInviteLinkOpensJoinConfirm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "joinable"]
        app.launchArguments += [UITestID.openURLArgument, UITestID.joinableInviteLink]
        app.launch()

        assertJoinConfirmShowsJoinableRoom(in: app)
        app.buttons[UITestID.joinConfirmJoin].tap()

        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForNonExistence(timeout: UITestID.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.buttons["home.room.\(UITestID.joinableRoomID)"].waitForExistence(timeout: UITestID.timeout))
    }

    /// 表示名を登録する前に招待リンクで開かれたら、S-01 を出し、登録した後に S-06 参加確認を開く
    @MainActor
    func testInviteLinkBeforeRegistrationOpensJoinConfirmAfterOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "first-launch-invited"]
        app.launchArguments += [UITestID.openURLArgument, UITestID.joinableInviteLink]
        app.launch()

        let nameField = app.textFields[UITestID.displayNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForNonExistence(timeout: UITestID.timeout))
        nameField.tap()
        nameField.typeText("ゆい")
        app.buttons[UITestID.startButton].tap()

        assertJoinConfirmShowsJoinableRoom(in: app)
    }

    /// S-06 にデモの参加できるルーム（夏の花火大会・作成者はるか）が出ている
    @MainActor
    private func assertJoinConfirmShowsJoinableRoom(in app: XCUIApplication) {
        let card = app.descendants(matching: .any)[UITestID.joinConfirmCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.label.contains("夏の花火大会"), card.label)
        XCTAssertTrue(card.label.contains("はるか"), card.label)
    }
}
