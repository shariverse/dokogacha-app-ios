//
//  SettingsUITests.swift
//  DokogachaUITests
//

import XCTest

/// S-15 設定の項目（03 の S-15）とライセンスの画面の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario one-room`）で動かす。
///
/// `-uiTesting` では StoreKit を使わず（`PurchaseCoordinator.disabled`）、Apple の認証の画面も出さない
/// （擬似のサーバーの `DemoAppleAuthorizer` が決まった ID トークンを返す）。購入・Safari・設定アプリは開かずに、行が出ることだけを確かめる
final class SettingsUITests: XCTestCase {
    /// S-15 の行の ID（`SettingsView.Identifier`）
    private enum Row {
        static let removeAds = "settings.removeAds"
        static let restore = "settings.restore"
        static let appleLink = "settings.appleLink"
        static let notifications = "settings.notifications"
        static let terms = "settings.terms"
        static let privacy = "settings.privacy"
        static let licenses = "settings.licenses"
        static let version = "settings.version"
    }

    /// ライセンスの画面（`LicensesView.Identifier.screen`）
    private static let licensesScreen = "licenses.screen"
    /// ライセンスの画面の Mochiy Pop One の行（`LicensesView.Identifier.row("mochiy-pop-one")`）
    private static let mochiyRow = "licenses.row.mochiy-pop-one"
    /// ライセンスの全文の画面（`LicenseDetailView.Identifier.screen`）
    private static let licenseDetail = "licenses.detail"
    /// ライセンスの全文（`LicenseDetailView.Identifier.text`）
    private static let licenseText = "licenses.detail.text"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ホームの歯車から S-15 を開く
    @MainActor
    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let gear = app.buttons[UITestID.settingsButton]
        XCTAssertTrue(gear.waitForExistence(timeout: UITestID.timeout))
        gear.tap()
        XCTAssertTrue(app.otherElements[UITestID.settingsScreen].waitForExistence(timeout: UITestID.timeout))
        return app
    }

    /// 要素（ボタンでも文字でも）を ID で探す
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// S-15 に 03 の項目が 03 の文言で並ぶ（購入・復元・Apple の連携・通知設定・利用規約・プライバシーポリシー・ライセンス・バージョン）
    @MainActor
    func testSettingsShowsAllItems() throws {
        let app = openSettings()

        let expected: [(String, String)] = [
            (Row.removeAds, "広告を非表示にする（¥480）"),
            (Row.restore, "購入を復元"),
            (Row.appleLink, "Apple でサインインを連携"),
            (Row.notifications, "通知設定"),
            (Row.terms, "利用規約"),
            (Row.privacy, "プライバシーポリシー"),
            (Row.licenses, "ライセンス"),
            (Row.version, "バージョン")
        ]
        var previousMinY = -CGFloat.infinity
        for (identifier, label) in expected {
            let row = element(identifier, in: app)
            XCTAssertTrue(row.waitForExistence(timeout: UITestID.timeout), identifier)
            XCTAssertTrue(row.label.contains(label), "\(identifier): \(row.label)")
            // 03 の S-15 の並び（上から順）
            XCTAssertGreaterThan(row.frame.minY, previousMinY, identifier)
            previousMinY = row.frame.minY
        }
        // バージョンは「1.0.0（1）」の形
        XCTAssertTrue(element(Row.version, in: app).label.contains("（"), element(Row.version, in: app).label)
    }

    /// 「Apple でサインインを連携」を押すと「連携済み」になり、押せなくなる（擬似のサーバーの Apple のアカウントに連携する）
    @MainActor
    func testLinkAppleShowsLinked() throws {
        let app = openSettings()

        let link = app.buttons[Row.appleLink]
        XCTAssertTrue(link.waitForExistence(timeout: UITestID.timeout))
        link.tap()

        let linked = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", Row.appleLink, "連携済み")
        ).firstMatch
        XCTAssertTrue(linked.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[Row.appleLink].exists)
    }

    /// 「ライセンス」を押すとライセンスの画面が開き、フォントを押すと OFL の全文が出る。戻ると設定に戻る
    @MainActor
    func testOpenLicenses() throws {
        let app = openSettings()

        let licenses = app.buttons[Row.licenses]
        XCTAssertTrue(licenses.waitForExistence(timeout: UITestID.timeout))
        if !licenses.isHittable {
            app.swipeUp()
        }
        licenses.tap()
        XCTAssertTrue(app.otherElements[Self.licensesScreen].waitForExistence(timeout: UITestID.timeout))

        let mochiy = app.buttons[Self.mochiyRow]
        XCTAssertTrue(mochiy.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(mochiy.label.contains("SIL Open Font License 1.1"), mochiy.label)
        mochiy.tap()
        XCTAssertTrue(app.otherElements[Self.licenseDetail].waitForExistence(timeout: UITestID.timeout))
        let text = element(Self.licenseText, in: app)
        XCTAssertTrue(text.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(text.label.contains("SIL OPEN FONT LICENSE"))

        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[Self.licensesScreen].waitForExistence(timeout: UITestID.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[UITestID.settingsScreen].waitForExistence(timeout: UITestID.timeout))
    }
}
