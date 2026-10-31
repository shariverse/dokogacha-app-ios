//
//  CloseRoomUITests.swift
//  DokogachaUITests
//

import XCTest

/// ルームの終了（F-44）と思い出のきっぷ（S-02）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario drawn-rooms`）で動かす。
///
/// `drawn-rooms` は、自分が作った「週末のランチ」とはるかが作った「春のお花見」がどちらも行き先が決まった（`drawn`）状態で、終了したルームは無い。
/// S-12 からの途中の終了（Discussion #155）は、自分が作った候補募集中のルームがある `room-with-candidates` で動かす
final class CloseRoomUITests: XCTestCase {
    /// 自分が作った行き先が決まったルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.drawnRoomID)`）
    private static let myDrawnRoomCard = "home.room.demo-room-drawn-mine"
    /// はるかが作った行き先が決まったルーム（春のお花見）のカード（`HomeView.Identifier.room(DemoScenario.othersDrawnRoomID)`）
    private static let othersDrawnRoomCard = "home.room.demo-room-drawn-others"
    /// 週末のランチの思い出のきっぷ（`HomeMemoryTickets.Identifier.ticket(DemoScenario.drawnRoomID)`）
    private static let myMemoryTicket = "home.memory.demo-room-drawn-mine"
    /// 候補募集中のルーム（年末の旅行）の思い出のきっぷ（`HomeMemoryTickets.Identifier.ticket(DemoScenario.roomID)`）
    private static let demoRoomMemoryTicket = "home.memory.demo-room"
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
        XCTAssertTrue(app.staticTexts[Self.ownerNote].waitForNonExistence(timeout: UITestID.timeout))

        // 確認のダイアログの「決定する」でルームを終了してホームへ戻る
        decide.tap()
        XCTAssertTrue(app.staticTexts["この行き先で決定しますか？"].waitForExistence(timeout: UITestID.timeout))
        let confirm = app.buttons["決定する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForNonExistence(timeout: UITestID.timeout))

        // 進行中のルームから消え、思い出のきっぷに「サンシャイン水族館 ゆき」・外れた候補 2 件で出る
        let ticket = app.buttons[Self.myMemoryTicket]
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(ticket.label.contains("週末のランチ"), ticket.label)
        XCTAssertTrue(ticket.label.contains("サンシャイン水族館"), ticket.label)
        XCTAssertTrue(ticket.label.contains("外れた候補 2件は次のルームで使えます"), ticket.label)
        XCTAssertTrue(app.buttons[Self.myDrawnRoomCard].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[Self.memoriesEmpty].waitForNonExistence(timeout: UITestID.timeout))

        // 思い出のきっぷから S-14 を閲覧のみで開く
        ticket.tap()
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.descendants(matching: .any)[UITestID.resultTicket].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[Self.decideButton].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[Self.ownerNote].waitForNonExistence(timeout: UITestID.timeout))
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
        XCTAssertTrue(app.buttons[Self.decideButton].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// 作成者が候補募集中のルーム（S-07）のヘッダーの設定から S-12 を開き、「ルームを終了する」→ 確認の「終了する」で、
    /// シートが閉じてホームに戻り、そのルームが進行中のルームから消える。抽選していないので思い出のきっぷにも出ない（Discussion #155）
    @MainActor
    func testOwnerEndsRoomEarlyFromRoomSettings() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[Self.memoriesEmpty].waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        app.buttons[UITestID.roomSettings].tap()
        let sheet = app.otherElements[UITestID.roomSettingsScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))

        // 項目の下の「ルームを終了する」（保存のボタンに隠れない位置まで送る）
        let endRoom = app.buttons[UITestID.roomSettingsEndRoom]
        XCTAssertTrue(endRoom.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(endRoom.scrollIntoView(in: app, above: app.buttons[UITestID.roomSettingsSave]))
        endRoom.tap()

        // 確認のダイアログ（03 の S-12 の文言）。iOS 26 では「キャンセル」のボタンを出さない（外を押すと閉じる）ので、「終了する」だけを押す
        XCTAssertTrue(app.staticTexts["ルームを終了しますか？"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["ルームを終了すると、候補の投稿やガチャができなくなります"].exists)
        let confirm = app.buttons["終了する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()

        // シートが閉じてホームに戻る。終了したルームが進行中のルームから消え、抽選していないので思い出のきっぷにも出ない
        // （空の表示のまま。見出しだけのセクションにならない）。トーストは 2.2 秒で消えるので、負荷で揺れないよう確かめない
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[Self.memoriesEmpty].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[Self.demoRoomMemoryTicket].exists)
    }

    /// ほかの人（はるか）が作ったルームの S-07 を開いている間に、はるかがルームを途中で終了すると、S-07 が閲覧のみになる:
    /// 下部が「このルームは終了しています」になり、準備OKを出さず・候補を追加を押せず、結果（S-14）も開かない。戻るとホームの進行中のルームから消える
    /// （`-ui-owner-ends-room`: 準備OKを押したら、作成者がルームを途中で終了したことにする。Discussion #155）
    @MainActor
    func testMemberSeesRoomEndedWhileOpen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms", UITestID.ownerEndsRoomArgument]
        app.launch()

        XCTAssertTrue(app.buttons[UITestID.demoRoomCard].waitForExistence(timeout: UITestID.timeout))
        let card = app.buttons[UITestID.othersRoomCard]
        XCTAssertTrue(card.scrollIntoView(in: app))
        card.tap()
        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomAddCandidate].waitForExistence(timeout: UITestID.timeout))

        let ready = app.buttons[UITestID.roomReady]
        XCTAssertTrue(ready.waitForExistence(timeout: UITestID.timeout))
        ready.tap()

        let ended = app.descendants(matching: .any)[UITestID.roomEnded]
        XCTAssertTrue(ended.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(ended.label.contains("このルームは終了しています"), ended.label)
        XCTAssertTrue(ready.waitForNonExistence(timeout: UITestID.timeout))
        // 「候補を追加」は行き先が決まったルームと同じく、出したまま押せなくする。候補が 0 件の案内は「候補はありません」だけ
        XCTAssertFalse(app.buttons[UITestID.roomAddCandidate].isEnabled)
        XCTAssertEqual(app.staticTexts[UITestID.roomEmpty].label, "候補はありません")
        XCTAssertFalse(app.buttons[UITestID.roomGacha].exists)
        XCTAssertFalse(app.otherElements[UITestID.resultScreen].exists)

        room.buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.waitForNonExistence(timeout: UITestID.timeout))
    }

    /// 途中で終了したルームを通知（終了の通知）から開くと、S-07 を閲覧のみで出す（結果は無いので S-14 は開かない）。
    /// ホームの進行中のルームには出ない（`ended-room`: はるかが作った春のお花見を、はるかが抽選の前に終了した）
    @MainActor
    func testOpenEndedRoomFromNotification() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting", "-demo-scenario", "ended-room",
            "-open-notification", #"{"type":"roomEnded","roomId":"demo-room-others","target":"room"}"#
        ]
        app.launch()

        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["春のお花見"].firstMatch.waitForExistence(timeout: UITestID.timeout))
        let ended = app.descendants(matching: .any)[UITestID.roomEnded]
        XCTAssertTrue(ended.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[UITestID.roomReady].exists)
        XCTAssertFalse(app.buttons[UITestID.roomAddCandidate].isEnabled)
        XCTAssertFalse(app.otherElements[UITestID.resultScreen].exists)

        room.buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.demoRoomCard].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(app.buttons[UITestID.othersRoomCard].exists)
    }
}
