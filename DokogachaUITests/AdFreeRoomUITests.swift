//
//  AdFreeRoomUITests.swift
//  DokogachaUITests
//

import XCTest

/// 広告非表示の購入者がいるルーム（S-07・02 の §7.2 F-51）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario ad-free-room`）で動かす。
///
/// `-uiTesting` では広告を読み込まない（`AdMode.disabled`）ので、バナーが出ないことは購入者がいないルームでも同じ。
/// バナーを出すかの判定は Unit テスト（`AdPolicyTests`）で確かめ、ここでは購入者のメッセージが出ることと、バナーの場所が無いことを確かめる
final class AdFreeRoomUITests: XCTestCase {
    /// 「◯◯さんのおかげで、このルームは広告なし」（`AdFreeNoticeSlot.identifier`）
    private static let adFreeNotice = "ad.freeNotice"
    /// バナー広告の場所（`BannerAdSlot.identifier`）
    private static let banner = "ad.banner"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ほかのメンバー（はるか）が広告非表示を買ったルームを、買っていない自分が開くと、最下部に
    /// 「はるかさんのおかげで、このルームは広告なし」が出て、バナーは出ない（02 の F-51 の AC「購入者がいるルームでは、未購入のメンバーにも広告が出ず、購入者名のメッセージが出る」）
    @MainActor
    func testSponsoredRoomShowsAdFreeNoticeInsteadOfBanner() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "ad-free-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        let notice = app.descendants(matching: .any)[Self.adFreeNotice]
        XCTAssertTrue(notice.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(notice.label, "はるかさんのおかげで、このルームは広告なし")
        XCTAssertTrue(notice.isHittable)
        // 下部の「ガチャを回す」の下に置く（重ならない）
        let gacha = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gacha.exists)
        XCTAssertLessThanOrEqual(gacha.frame.maxY, notice.frame.minY)
        XCTAssertFalse(app.descendants(matching: .any)[Self.banner].exists)
    }

    /// 購入者がいないルームでは、メッセージを出さない
    @MainActor
    func testRoomWithoutSponsorShowsNoNotice() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomGacha].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.descendants(matching: .any)[Self.adFreeNotice].exists)
    }
}
