//
//  ReportCandidateUITests.swift
//  DokogachaUITests
//

import XCTest

/// 投稿の報告（F-14）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario room-with-candidates`）で動かす
final class ReportCandidateUITests: XCTestCase {
    /// はるかの候補のひとこと（`DemoScenario`）
    private static let note = "ペンギンが空を飛ぶ水槽が見たい"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 他人の候補の S-10 で「…」→「この投稿を報告」→ 理由「スパム」を選ぶと、トースト「報告しました」が出て、
    /// その候補のひとことと参考 URL が消え、「…」のメニューも無くなる。S-07 に戻っても、その候補のひとことは出ない（02 の §3.5）
    @MainActor
    func testReportCandidateHidesNoteAndURL() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        // はるかの投稿（サンシャイン水族館）を開く。一覧の下の方にあるので、見えるまでスクロールする
        let others = app.otherElements[UITestID.candidateCard(UITestID.othersCandidateID)]
        if !others.waitForExistence(timeout: UITestID.timeout) || !others.isHittable {
            app.swipeUp()
        }
        others.buttons.matching(NSPredicate(format: "label CONTAINS %@", "サンシャイン水族館")).firstMatch.tap()
        let detail = app.otherElements[UITestID.candidateDetailScreen]
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(detail.staticTexts[Self.note].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.descendants(matching: .any)[UITestID.candidateDetailURL].exists)

        // 「…」→「この投稿を報告」→ 理由を選ぶ
        app.buttons[UITestID.candidateDetailMore].tap()
        let report = app.buttons[UITestID.candidateDetailReport]
        XCTAssertTrue(report.waitForExistence(timeout: UITestID.timeout))
        report.tap()
        let spam = app.buttons["スパム"]
        XCTAssertTrue(spam.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons["不適切な内容"].exists)
        XCTAssertTrue(app.buttons["その他"].exists)
        spam.tap()

        // トーストが出て、ひとことと参考 URL・「…」が消える（場所名は残る）
        XCTAssertTrue(app.staticTexts["報告しました"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(detail.staticTexts[Self.note].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.descendants(matching: .any)[UITestID.candidateDetailURL].exists)
        XCTAssertFalse(app.buttons[UITestID.candidateDetailMore].exists)
        XCTAssertTrue(detail.staticTexts["サンシャイン水族館"].exists)

        // 閉じて S-07 に戻っても、その候補のひとことは出ない
        app.buttons[UITestID.candidateDetailClose].tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(others.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.staticTexts[Self.note].exists)
    }
}
