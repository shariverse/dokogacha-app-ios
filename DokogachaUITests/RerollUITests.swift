//
//  RerollUITests.swift
//  DokogachaUITests
//

import XCTest

/// S-14 の引き直し（F-43）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario several-rooms`）で動かす。
///
/// 解禁済みのルーム（週末のランチ。自分・はるか・そうたの 3 人）で回してから、S-14 で引き直しを提案する。
/// ここでは自分の票だけを確かめる。ほかのメンバーの賛成で可決して回し直すまでは、`-ui-auto-members` で
/// ほかのメンバーの票を返す `ScenarioUITests` で確かめる
final class RerollUITests: XCTestCase {
    /// ホームの解禁済みのルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.unlockedRoomID)`）
    private static let unlockedRoomCard = "home.room.demo-room-unlocked"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// S-14 で「引き直しを提案（過半数の賛成で1回まで）」を押すと、自分の賛成で「賛成を集めています…（1/3人）」の投票中になり、
    /// 賛成／反対のボタンが出る。反対に変えると賛成の数が減り、賛成に戻すと増える
    @MainActor
    func testProposeRerollShowsVoting() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms"]
        app.launch()
        openResult(app)

        let propose = app.buttons[UITestID.resultRerollPropose]
        XCTAssertTrue(propose.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(propose.label, "引き直しを提案（過半数の賛成で1回まで）")
        XCTAssertTrue(propose.isEnabled)
        propose.tap()

        // 状態の表示は押せないボタンではなく文として読む（PR #76 の持ち越し）
        let status = app.staticTexts[UITestID.resultRerollStatus]
        XCTAssertTrue(status.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(status.label, "賛成を集めています…（1/3人）")
        XCTAssertFalse(app.buttons[UITestID.resultRerollStatus].exists)
        XCTAssertTrue(propose.waitForNonExistence(timeout: UITestID.timeout))
        let approve = app.buttons[UITestID.resultRerollApprove]
        let reject = app.buttons[UITestID.resultRerollReject]
        XCTAssertTrue(approve.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(approve.label, "引き直しに賛成")
        XCTAssertTrue(approve.isSelected)
        XCTAssertEqual(reject.label, "引き直しに反対")
        XCTAssertFalse(reject.isSelected)

        // 反対に変えると賛成は 0 人。賛成に戻すと 1 人
        reject.tap()
        XCTAssertTrue(wait(for: status, label: "賛成を集めています…（0/3人）"))
        XCTAssertTrue(reject.isSelected)
        XCTAssertFalse(approve.isSelected)
        approve.tap()
        XCTAssertTrue(wait(for: status, label: "賛成を集めています…（1/3人）"))
        XCTAssertTrue(approve.isSelected)
    }

    /// ホームから解禁済みのルームを開き、ガチャを回してカプセルを開け、S-14 を出す
    @MainActor
    private func openResult(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.buttons[Self.unlockedRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        card.tap()
        let gachaButton = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gachaButton.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        gachaButton.tap()
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        lever.tap()
        let capsule = app.buttons["カプセルを開ける"]
        XCTAssertTrue(capsule.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        capsule.tap()
        XCTAssertTrue(
            app.otherElements[UITestID.resultScreen].waitForExistence(timeout: UITestID.timeout),
            file: file,
            line: line
        )
    }

    /// 要素の文言が `label` になるまで待つ
    private func wait(for element: XCUIElement, label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: UITestID.timeout)
            == .completed
    }
}
