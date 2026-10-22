//
//  GachaUITests.swift
//  DokogachaUITests
//

import XCTest

/// S-13 ガチャの UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario several-rooms`）で動かす。
///
/// `-uiTesting` ではガチャを常に「視差効果を減らす」で動かす（`MainNavigationView`）ので、演出を待たずに次の段階に進む
final class GachaUITests: XCTestCase {
    /// ホームの解禁済みのルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.unlockedRoomID)`）
    private static let unlockedRoomCard = "home.room.demo-room-unlocked"
    /// S-13（`GachaView.Identifier.screen`）
    private static let gachaScreen = "gacha.screen"
    /// S-13 のタイトル（`GachaView.Identifier.title`）
    private static let gachaTitle = "gacha.title"
    /// S-13 の「カプセル N個 · 共感ブースト」（`GachaView.Identifier.capsuleCount`）
    private static let gachaCapsuleCount = "gacha.capsuleCount"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 解禁済みのルーム（S-07）の「ガチャを回す」で S-13 が開き、レバーを回すとカプセルが出て、カプセルを開けると
    /// S-07 に戻り、ルームは行き先が決まった状態（「ガチャを回す」が無い）になる（F-40・S-13。S-14 はタスク 28）
    @MainActor
    func testTurnLeverAndOpenCapsule() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms"]
        app.launch()

        let card = app.buttons[Self.unlockedRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let gachaButton = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gachaButton.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(gachaButton.label, "ガチャを回す")
        gachaButton.tap()

        // S-13: 待機の文言とカプセルの数。いいねの効き方だけを読む（数はドームのラベルで読む）
        let screen = app.otherElements[Self.gachaScreen]
        XCTAssertTrue(screen.waitForExistence(timeout: UITestID.timeout))
        let title = app.staticTexts[Self.gachaTitle]
        XCTAssertTrue(title.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(title.label, "レバーを回してね")
        XCTAssertTrue(app.staticTexts["結果はメンバー全員の画面に同時に出ます"].exists)
        XCTAssertEqual(app.staticTexts[Self.gachaCapsuleCount].label, "共感ブースト")
        let dome = screen.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ガチャ。カプセル 3個")).firstMatch
        XCTAssertTrue(dome.exists)
        XCTAssertFalse(app.buttons["カプセルを開ける"].exists)

        // レバーを回すと、取り出し口にカプセルが出る。レバーはもう押せない
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.isEnabled)
        lever.tap()
        let capsule = app.buttons["カプセルを開ける"]
        XCTAssertTrue(capsule.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(title.label, "カプセルをタップ！")
        XCTAssertTrue(app.staticTexts["開けると行き先が決まります"].exists)
        XCTAssertFalse(lever.isEnabled)

        // カプセルを開けると S-07 に戻り、ルームは行き先が決まっている
        capsule.tap()
        XCTAssertTrue(screen.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["行き先決定"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[UITestID.roomGacha].exists)
    }
}
