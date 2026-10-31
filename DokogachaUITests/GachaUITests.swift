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

    /// 解禁済みのルーム（S-07）の「ガチャを回す」で S-13 が開き、レバーを回すと、カプセルを押さなくても
    /// 同じカバーの中で S-14 結果（行き先きっぷ）まで進む（F-40〜42・S-13・S-14。Issue #158）。S-14 から戻ると S-07 は行き先が決まった状態になり、
    /// 「行き先きっぷを見る」でもう一度 S-14 を開ける。ホームからルームを開き直すと、S-14 を自動で出す（03 の §2）
    @MainActor
    func testTurnLeverShowsResultWithoutTappingCapsule() throws {
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

        // レバーを回すと、カプセルを押さなくても S-14 に替わる（押すカプセルのボタンは出ない）
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.isEnabled)
        lever.tap()
        assertResultShown(app)
        XCTAssertTrue(screen.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons["カプセルを開ける"].exists)

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

    /// 結果の演出ごとに、レバーを回したら演出の後に S-14 の見出し・きっぷ・ボタンが出そろう（演出の途中で止まらない。Issue #158）。
    /// S-13 は UI テストではいつも「視差効果を減らす」で動く
    @MainActor
    func testResultRevealCompletesForEachStyle() throws {
        for style in ["flap", "capsule", "issue"] {
            try XCTContext.runActivity(named: style) { _ in
                try playGachaAndWaitForResult(revealArguments: ["-result-animation", style])
            }
        }
    }

    /// 「視差効果を減らす」でも、結果の演出（標準のパタパタ行き先表示）の後に S-14 が出そろう
    @MainActor
    func testResultRevealCompletesWithReducedMotion() throws {
        try playGachaAndWaitForResult(revealArguments: ["-result-animation", "flap", "-ui-reduce-motion"])
    }

    /// 解禁済みのルームでレバーを回し、結果の演出を流してから S-14 が出そろうのを確かめる
    @MainActor
    private func playGachaAndWaitForResult(revealArguments: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms"] + revealArguments
        app.launch()
        defer { app.terminate() }

        let card = app.buttons[Self.unlockedRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        card.tap()
        let gachaButton = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gachaButton.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        gachaButton.tap()
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        lever.tap()
        assertResultShown(app, file: file, line: line)
        // 演出を終えたら、下部の「この行き先で決定」（作成者）も出る
        XCTAssertTrue(app.buttons["この行き先で決定"].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
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
        let openInMaps = app.buttons[UITestID.resultOpenInMaps]
        XCTAssertTrue(openInMaps.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(openInMaps.isEnabled, file: file, line: line)
        XCTAssertTrue(app.buttons[UITestID.resultShare].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
    }
}
