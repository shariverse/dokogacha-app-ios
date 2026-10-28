//
//  PastIdeasUITests.swift
//  DokogachaUITests
//

import XCTest

extension UITestID {
    /// S-08 の「過去のアイデア」のタブ（`DGTabSwitch` のボタン。文言で探す）
    static let pastIdeasTab = "過去のアイデア"
    /// `past-ideas` の鎌倉大仏の「持ち込む」（`PastIdeasSection.Identifier.bring("demo-room-past-summer_c2")`）
    static let kamakuraBring = "addCandidate.pastIdea.demo-room-past-summer_c2.bring"
    /// `past-ideas` の江の島（自分の投稿と同じ場所）の「追加済み」（`PastIdeasSection.Identifier.bring("demo-room-past-summer_c3")`）
    static let enoshimaBring = "addCandidate.pastIdea.demo-room-past-summer_c3.bring"
    /// `past-ideas` の夏の日帰りの見出し（`PastIdeasSection.Identifier.group(DemoScenario.pastSummerRoomID)`）
    static let summerGroup = "addCandidate.pastIdeas.group.demo-room-past-summer"
}

/// S-08 の「過去のアイデア」（F-13）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario past-ideas`）で動かす
final class PastIdeasUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ルーム（S-07）の「候補を追加」から S-08 の「過去のアイデア」を開くと、ルームごとの見出しと行が出る。
    /// 「持ち込む」で S-09 を開いて「候補に追加」を押すと S-07 に戻り、持ち込んだ候補が一覧に並ぶ（F-13・06 の §2 の UI テスト 3）
    @MainActor
    func testBringPastIdeaToRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "past-ideas"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let addButton = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()

        // S-08: 「過去のアイデア」のタブに切り替える
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForExistence(timeout: UITestID.timeout))
        let tab = app.buttons[UITestID.pastIdeasTab]
        XCTAssertTrue(tab.waitForExistence(timeout: UITestID.timeout))
        tab.tap()
        XCTAssertTrue(tab.isSelected)

        // 見出しはルーム名・日付・「◯◯ ゆき」をまとめて読む。自分の投稿と同じ場所は「追加済み」で押せない
        let header = app.descendants(matching: .any)[UITestID.summerGroup]
        XCTAssertTrue(header.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(header.label.hasPrefix("夏の日帰り、"))
        XCTAssertTrue(header.label.hasSuffix("城ヶ島 ゆき"))
        let enoshima = app.buttons[UITestID.enoshimaBring]
        XCTAssertTrue(enoshima.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(enoshima.label, "追加済み")
        XCTAssertFalse(enoshima.isEnabled)

        let bring = app.buttons[UITestID.kamakuraBring]
        XCTAssertTrue(bring.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(bring.label, "持ち込む")
        bring.tap()

        // S-09: 場所名と前回のカテゴリが出ている。そのまま投稿する
        let sheet = app.otherElements[UITestID.postCandidateScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.staticTexts[UITestID.postCandidatePlaceName].firstMatch.label.contains("鎌倉大仏"))
        XCTAssertEqual(sheet.buttons[UITestID.postCandidateCategory].value as? String, "寺社")
        sheet.buttons[UITestID.postCandidateSubmit].tap()

        // S-07 に戻り、持ち込んだ候補が一覧に並んでいる
        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(room.staticTexts["鎌倉大仏"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.postCandidateScreen].waitForNonExistence(timeout: UITestID.timeout))
    }
}
