//
//  CloseRoomUITests.swift
//  DokogachaUITests
//

import XCTest

/// ルームの終了（F-44）と思い出のきっぷ（S-02）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario drawn-rooms`）で動かす。
///
/// `drawn-rooms` は、自分が作った「週末のランチ」とはるかが作った「春のお花見」がどちらも行き先が決まった（`drawn`）状態で、終了したルームは無い
final class CloseRoomUITests: XCTestCase {
    /// 自分が作った行き先が決まったルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.drawnRoomID)`）
    private static let myDrawnRoomCard = "home.room.demo-room-drawn-mine"
    /// はるかが作った行き先が決まったルーム（春のお花見）のカード（`HomeView.Identifier.room(DemoScenario.othersDrawnRoomID)`）
    private static let othersDrawnRoomCard = "home.room.demo-room-drawn-others"
    /// 週末のランチの思い出のきっぷ（`HomeMemoryTickets.Identifier.ticket(DemoScenario.drawnRoomID)`）
    private static let myMemoryTicket = "home.memory.demo-room-drawn-mine"
    /// 思い出のきっぷの空の表示（`HomeView.Identifier.memoriesEmpty`）
    private static let memoriesEmpty = "home.memories.empty"
    /// S-14 の「この行き先で決定」（`ResultCloseSection.Identifier.decide`）
    private static let decideButton = "result.decide"
    /// S-14 の「作成者が決定するとルームが終了します」（`ResultCloseSection.Identifier.ownerNote`）
    private static let ownerNote = "result.ownerNote"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 作成者が S-14 で「この行き先で決定」→ 確認 →「決定する」でホームに戻り、進行中のルームから消えて思い出のきっぷに出る。
    /// 思い出のきっぷを押すと S-14 が閲覧のみ（決定のボタンも説明も無い）で開く（F-44・03 の S-02・S-14・§2）
    @MainActor
    func testOwnerDecidesAndMemoryTicketAppears() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "drawn-rooms"]
        app.launch()

        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[Self.memoriesEmpty].waitForExistence(timeout: UITestID.timeout))
        let card = app.buttons[Self.myDrawnRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()

        // 行き先が決まったルームを開くと S-14 が出る。作成者には「この行き先で決定」
        let result = app.otherElements[UITestID.resultScreen]
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout))
        let decide = app.buttons[Self.decideButton]
        XCTAssertTrue(decide.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(decide.label, "この行き先で決定")
        XCTAssertFalse(app.staticTexts[Self.ownerNote].exists)

        // 確認のダイアログの「決定する」でルームを終了してホームへ戻る
        decide.tap()
        XCTAssertTrue(app.staticTexts["この行き先で決定しますか？"].waitForExistence(timeout: UITestID.timeout))
        let confirm = app.buttons["決定する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.otherElements[UITestID.roomScreen].exists)

        // 進行中のルームから消え、思い出のきっぷに「サンシャイン水族館 ゆき」・外れた候補 2 件で出る
        let ticket = app.buttons[Self.myMemoryTicket]
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(ticket.label.contains("週末のランチ"), ticket.label)
        XCTAssertTrue(ticket.label.contains("サンシャイン水族館"), ticket.label)
        XCTAssertTrue(ticket.label.contains("外れた候補 2件は次のルームで使えます"), ticket.label)
        XCTAssertFalse(app.buttons[Self.myDrawnRoomCard].exists)
        XCTAssertFalse(app.staticTexts[Self.memoriesEmpty].exists)

        // 思い出のきっぷから S-14 を閲覧のみで開く
        ticket.tap()
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.descendants(matching: .any)[UITestID.resultTicket].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[Self.decideButton].exists)
        XCTAssertFalse(app.staticTexts[Self.ownerNote].exists)
        result.buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout))
    }

    /// 作成者以外の S-14 には、ボタンの代わりに「作成者が決定するとルームが終了します」を出す（02 の §6.3）
    @MainActor
    func testMemberSeesOwnerNote() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "drawn-rooms"]
        app.launch()

        let card = app.buttons[Self.othersDrawnRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.resultScreen].waitForExistence(timeout: UITestID.timeout))
        let note = app.staticTexts[Self.ownerNote]
        XCTAssertTrue(note.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(note.label, "作成者が決定するとルームが終了します")
        XCTAssertFalse(app.buttons[Self.decideButton].exists)
    }
}
