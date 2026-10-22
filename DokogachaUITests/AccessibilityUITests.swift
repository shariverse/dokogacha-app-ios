//
//  AccessibilityUITests.swift
//  DokogachaUITests
//

import XCTest

/// アクセシビリティ（06 の §3「VoiceOver で操作できる」）の UI テスト。
/// アイコンだけのボタンの名前と、入力欄のエラーを 1 回だけ読むこと（タスク 42）を、XCUIElement のラベルで確かめる
final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ホーム・ルームのアイコンだけのボタン（設定の歯車・戻る・ルーム設定の歯車）に名前がある
    @MainActor
    func testIconOnlyButtonsHaveLabels() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let settings = app.buttons[UITestID.settingsButton]
        XCTAssertTrue(settings.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(settings.label, "設定")

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons["戻る"].waitForExistence(timeout: UITestID.timeout))
        let roomSettings = app.buttons["room.settings"]
        XCTAssertTrue(roomSettings.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(roomSettings.label, "ルーム設定")
    }

    /// 表示名が長すぎると、入力欄の名前の後ろにエラーを読み、エラーの文は別の要素として読まない（同じ文を 2 回読まない。PR #37 の持ち越し）
    @MainActor
    func testTextFieldReadsErrorOnce() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "first-launch"]
        app.launch()

        let field = app.textFields[UITestID.displayNameField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(field.label, "表示名")
        field.tap()
        field.typeText("あいうえおかきくけこさ")

        let error = "10文字以内で入力してください"
        XCTAssertTrue(field.waitForLabel("表示名、\(error)"), field.label)
        XCTAssertFalse(app.staticTexts[error].exists)
    }
}
