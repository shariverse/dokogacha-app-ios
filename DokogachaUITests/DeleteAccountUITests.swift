//
//  DeleteAccountUITests.swift
//  DokogachaUITests
//

import XCTest

/// S-15 設定の「アカウントを削除」（02 の §2.6 F-06）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario one-room`）で動かす。
///
/// 確認のダイアログ（02 の F-06 の文言）→「削除する」→ サインアウトして S-01 オンボーディングに戻るまでと、
/// 「キャンセル」では何もしないことを確かめる。デモのルーム（年末の旅行）は自分が作成者なので、削除すると終了し、
/// 新しいアカウントのホームには出ない
final class DeleteAccountUITests: XCTestCase {
    /// S-15 の「アカウントを削除」の行（`SettingsView.Identifier.deleteAccount`）
    private static let deleteRow = "settings.deleteAccount"
    /// 確認のダイアログの見出し
    private static let alertTitle = "アカウントを削除しますか？"
    /// 確認のダイアログの本文（02 の F-06 の文言と、作成したルームが終了すること）
    private static let alertMessage = "アカウントを削除すると、参加中のルームから退出し、元に戻せません。作成したルームは終了します。"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ホームの歯車から S-15 を開き、「アカウントを削除」を押して確認のダイアログを出す
    @MainActor
    private func openDeletionAlert() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let gear = app.buttons[UITestID.settingsButton]
        XCTAssertTrue(gear.waitForExistence(timeout: UITestID.timeout))
        gear.tap()
        XCTAssertTrue(app.otherElements[UITestID.settingsScreen].waitForExistence(timeout: UITestID.timeout))

        let row = app.buttons[Self.deleteRow]
        XCTAssertTrue(row.waitForExistence(timeout: UITestID.timeout))
        if !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.label.contains("アカウントを削除"), row.label)
        row.tap()

        let alert = app.alerts[Self.alertTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(alert.staticTexts[Self.alertMessage].exists)
        return (app, alert)
    }

    /// 「削除する」でアカウントを削除し、S-01 に戻る。表示名を入れ直すと、新しいアカウントのホーム（ルームは無い）が開く
    @MainActor
    func testDeleteAccountReturnsToOnboarding() throws {
        let (app, alert) = openDeletionAlert()
        alert.buttons["削除する"].tap()

        let field = app.textFields[UITestID.displayNameField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.otherElements[UITestID.settingsScreen].exists)

        field.tap()
        field.typeText("ゆい")
        app.buttons[UITestID.startButton].tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        // 前のアカウントのルーム（作成者だったので終了した）は、新しいアカウントには出ない
        XCTAssertTrue(app.descendants(matching: .any)[UITestID.roomsEmpty].firstMatch.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.descendants(matching: .any)[UITestID.demoRoomCard].firstMatch.exists)
    }

    /// 「キャンセル」では削除せず、設定の画面のまま
    @MainActor
    func testCancelKeepsAccount() throws {
        let (app, alert) = openDeletionAlert()
        alert.buttons["キャンセル"].tap()

        XCTAssertTrue(alert.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.settingsScreen].exists)
        XCTAssertTrue(app.buttons[UITestID.displayNameRow].label.contains("たくみ"))
    }
}
