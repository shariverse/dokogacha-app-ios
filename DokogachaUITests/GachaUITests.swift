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
    /// 同じカバーの中で S-14 結果（行き先きっぷ）に替わる（F-40〜42・S-13・S-14）。S-14 から戻ると S-07 は行き先が決まった状態になり、
    /// 「行き先きっぷを見る」でもう一度 S-14 を開ける。ホームからルームを開き直すと、S-14 を自動で出す（03 の §2）
    @MainActor
    func testTurnLeverOpenCapsuleAndShowResult() throws {
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
        XCTAssertTrue(app.staticTexts["結果はメンバー全員の画面に同時に出ます"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(app.staticTexts[Self.gachaCapsuleCount].label, "共感ブースト")
        let dome = screen.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ガチャ。カプセル 3個")).firstMatch
        XCTAssertTrue(dome.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons["カプセルを開ける"].waitForNonExistence(timeout: UITestID.timeout))

        // レバーを回すと、取り出し口にカプセルが出る。レバーはもう押せない
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.isEnabled)
        lever.tap()
        let capsule = app.buttons["カプセルを開ける"]
        XCTAssertTrue(capsule.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(title.label, "カプセルをタップ！")
        XCTAssertTrue(app.staticTexts["開けると行き先が決まります"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(lever.isEnabled)

        // カプセルを開けると S-14 に替わる
        capsule.tap()
        assertResultShown(app)
        XCTAssertTrue(screen.waitForNonExistence(timeout: UITestID.timeout))

        // 戻ると S-07。行き先が決まっていて、「行き先きっぷを見る」でもう一度開ける
        app.otherElements[UITestID.resultScreen].buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["行き先決定"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomGacha].waitForNonExistence(timeout: UITestID.timeout))
        let resultButton = app.buttons[UITestID.roomResult]
        XCTAssertTrue(resultButton.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(resultButton.label, "行き先きっぷを見る")
        resultButton.tap()
        assertResultShown(app)

        // S-14 → S-07 → ホームに戻り、ルームを開き直すと S-14 を自動で出す
        app.otherElements[UITestID.resultScreen].buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(app.otherElements[UITestID.resultScreen].waitForNonExistence(timeout: UITestID.timeout))
        app.otherElements[UITestID.roomScreen].buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        assertResultShown(app)
    }

    /// S-14 が出て、見出し・行き先きっぷ・「マップで開く」「きっぷを共有」がある
    @MainActor
    private func assertResultShown(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let result = app.otherElements[UITestID.resultScreen]
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        let heading = app.staticTexts[UITestID.resultTitle]
        XCTAssertTrue(heading.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertEqual(heading.label, "行き先が決まりました", file: file, line: line)
        let ticket = result.descendants(matching: .any)[UITestID.resultTicket]
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(ticket.label.hasPrefix("行き先きっぷ、週末のランチ。"), file: file, line: line)
        XCTAssertTrue(app.buttons[UITestID.resultOpenInMaps].isEnabled, file: file, line: line)
        XCTAssertTrue(app.buttons[UITestID.resultShare].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
    }
}
