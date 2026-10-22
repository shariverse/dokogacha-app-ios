//
//  OfflineUITests.swift
//  DokogachaUITests
//

import XCTest

/// オフライン（02 の §9）の UI テスト。Simulator の回線はテストから切れないので、起動引数 `-network-offline` で
/// オフラインのことにする（`NetworkStatus` が固定の状態を流す）。擬似のサーバーの購読は、Firestore のキャッシュの代わりに値を返す
final class OfflineUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// オフラインでは、ホームとルームの上端に「オフラインです」のバナーが出て、閲覧はできる。
    /// オンライン必須の「準備OK」を押すと、送らずにトースト「オフラインのため操作できません」を出し、人数は変わらない
    @MainActor
    func testOfflineShowsBannerAndBlocksReady() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates", UITestID.networkOfflineArgument]
        app.launch()

        let banner = app.descendants(matching: .any)[UITestID.offlineBanner]
        XCTAssertTrue(banner.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(banner.label, "オフラインです")

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        // バナーは画面の上端に出し、カードに重ならない
        XCTAssertLessThanOrEqual(banner.frame.maxY, card.frame.minY)
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(banner.exists)

        let readyCount = app.staticTexts[UITestID.roomReadyCount]
        XCTAssertTrue(readyCount.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(readyCount.label, "準備OK 0/4人")
        let ready = app.buttons[UITestID.roomReady]
        ready.tap()
        XCTAssertTrue(app.staticTexts["オフラインのため操作できません"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(readyCount.label, "準備OK 0/4人")
        XCTAssertEqual(ready.label, "準備OK")
    }

    /// オンラインでは、バナーを出さない
    @MainActor
    func testOnlineShowsNoBanner() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        XCTAssertTrue(app.buttons[UITestID.demoRoomCard].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.descendants(matching: .any)[UITestID.offlineBanner].exists)
    }
}
