//
//  DokogachaUITests.swift
//  DokogachaUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

/// 起動の流れ（F-01）とホーム（S-02）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす
final class DokogachaUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 初回起動（表示名が無い）では S-01 が出て、表示名を入れて「はじめる」を押すとホームへ進む
    @MainActor
    func testFirstLaunchShowsOnboardingAndRegistersDisplayName() throws {
        let app = XCUIApplication()
        // Firebase を初期化せず、メモリ上の擬似のサーバーで動かす（LaunchContext.uiTestingArgument）
        app.launchArguments += ["-uiTesting", "-demo-scenario", "first-launch"]
        app.launch()

        let field = app.textFields[UITestID.displayNameField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestID.timeout))
        let start = app.buttons[UITestID.startButton]
        XCTAssertTrue(start.waitForExistence(timeout: UITestID.timeout))
        // 入力が空のときは押せない
        XCTAssertFalse(start.isEnabled)

        field.tap()
        field.typeText("ゆい")
        XCTAssertTrue(start.isEnabled)
        start.tap()

        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(field.waitForNonExistence(timeout: UITestID.timeout))
    }

    /// 表示名を登録済み（2 回目の起動）では、S-01 を出さずにホームが開く
    @MainActor
    func testRegisteredUserSkipsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "empty"]
        app.launch()

        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.textFields[UITestID.displayNameField].waitForNonExistence(timeout: UITestID.timeout))
        // ルームが無いので、進行中のルームは空の表示
        XCTAssertTrue(app.staticTexts[UITestID.roomsEmpty].waitForExistence(timeout: UITestID.timeout))
    }

    /// 進行中のルームがあればホームにカードが並び、押すとルーム画面へ進み、戻るとホームに戻る
    @MainActor
    func testHomeListsRoomAndOpensRoomScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.label.contains("年末の旅行"))
        XCTAssertTrue(app.staticTexts[UITestID.roomsEmpty].waitForNonExistence(timeout: UITestID.timeout))

        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
    }

    /// ホームから「ルームを作る」→ 名前を入れて「ルームを作成」→ 招待の画面に招待コードが出る。
    /// 「ルームへ進む」でルーム画面に出て、戻るとホームに戻る（S-03 には戻らない。03 の §1）
    @MainActor
    func testCreateRoomShowsInviteCode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "empty"]
        app.launch()

        let createRoom = app.buttons[UITestID.createRoomButton]
        XCTAssertTrue(createRoom.waitForExistence(timeout: UITestID.timeout))
        createRoom.tap()

        let name = app.textFields[UITestID.roomNameField]
        XCTAssertTrue(name.waitForExistence(timeout: UITestID.timeout))
        let submit = app.buttons[UITestID.createRoomSubmit]
        XCTAssertTrue(submit.waitForExistence(timeout: UITestID.timeout))
        // ルーム名が空のときは押せない（F-02 の AC）
        XCTAssertFalse(submit.isEnabled)

        name.tap()
        name.typeText("年末の旅行")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(app.otherElements[UITestID.inviteScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["年末の旅行"].waitForExistence(timeout: UITestID.timeout))
        let code = app.buttons[UITestID.inviteCode]
        XCTAssertTrue(code.waitForExistence(timeout: UITestID.timeout))
        // 招待コードは 3 文字ずつハイフンで区切って出す（`0 O 1 I` は使わない）
        let pattern = "[A-HJ-NP-Z2-9]{3}-[A-HJ-NP-Z2-9]{3}"
        XCTAssertNotNil(code.label.range(of: pattern, options: .regularExpression), code.label)

        app.buttons[UITestID.openRoomButton].tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.createRoomScreen].waitForNonExistence(timeout: UITestID.timeout))
        // 作ったルームがホームに並ぶ
        XCTAssertTrue(app.staticTexts[UITestID.roomsEmpty].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// ホームから「招待コードで参加」→ 存在しないコードでは入力欄の下にエラー → 正しいコード（小文字・ハイフンなし）を入れて
    /// 「参加する」→ S-06 にルーム名が出る → 「参加する」でシートが閉じてルーム画面が開く（F-04 の AC）。
    /// 戻るとホームに参加したルームが並ぶ
    @MainActor
    func testJoinRoomByInviteCode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "joinable"]
        app.launch()

        let joinByCode = app.buttons[UITestID.joinByCodeButton]
        XCTAssertTrue(joinByCode.waitForExistence(timeout: UITestID.timeout))
        joinByCode.tap()

        let field = app.textFields[UITestID.joinCodeField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestID.timeout))
        let submit = app.buttons[UITestID.joinCodeSubmit]
        XCTAssertTrue(submit.waitForExistence(timeout: UITestID.timeout))
        // 6 文字を入れるまでは押せない
        XCTAssertFalse(submit.isEnabled)

        field.tap()
        field.typeTextByCharacter("zzzzzz")
        XCTAssertTrue(field.waitForValue("ZZZ-ZZZ"), field.value as? String ?? "")
        XCTAssertTrue(submit.waitForEnabled())
        submit.tap()
        let error = app.staticTexts[UITestID.joinCodeError]
        XCTAssertTrue(error.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(error.label, "招待コードが見つかりません")

        // 入れ直す（全部消してから、デモの参加できるルームのコードを小文字・ハイフンなしで打つ）。
        // 削除キーをまとめて打つと負荷が高いときに抜けるので、1 文字ずつ値が変わるのを確かめながら消して打つ
        field.clearText()
        field.typeTextByCharacter("qw58rt")
        XCTAssertTrue(field.waitForValue("QW5-8RT"), field.value as? String ?? "")
        XCTAssertTrue(error.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(submit.waitForEnabled())
        submit.tap()

        let card = app.descendants(matching: .any)[UITestID.joinConfirmCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(card.label.contains("夏の花火大会"), card.label)
        XCTAssertTrue(card.label.contains("はるか"), card.label)
        app.buttons[UITestID.joinConfirmJoin].tap()

        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.joinConfirmScreen].waitForNonExistence(timeout: UITestID.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons["home.room.\(UITestID.joinableRoomID)"].waitForExistence(timeout: UITestID.timeout))
    }

    /// ナビゲーションバーを隠した画面でも、画面の左端からのスワイプで戻れる（`InteractivePopGesture`）
    @MainActor
    func testEdgeSwipeGoesBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        swipeFromLeftEdge(app)
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// 画面の左端から右へスワイプする（端からの戻る操作。`swipeRight()` は端から始まらないので座標で動かす）
    @MainActor
    private func swipeFromLeftEdge(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// ホームの歯車から設定（S-15）を開き、表示名を変えて保存すると行の名前が変わり、戻ってから開き直しても新しい名前のまま
    @MainActor
    func testChangeDisplayNameFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let gear = app.buttons[UITestID.settingsButton]
        XCTAssertTrue(gear.waitForExistence(timeout: UITestID.timeout))
        gear.tap()
        XCTAssertTrue(app.otherElements[UITestID.settingsScreen].waitForExistence(timeout: UITestID.timeout))

        // 今の名前が届いたら行に出る
        let row = app.buttons[UITestID.displayNameRow]
        let currentRow = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", UITestID.displayNameRow, "たくみ")
        ).firstMatch
        XCTAssertTrue(currentRow.waitForExistence(timeout: UITestID.timeout))
        row.tap()

        // シートは今の名前を入れて開き、同じ名前のままでは保存できない
        let field = app.textFields[UITestID.nameEditorField]
        XCTAssertTrue(field.waitForExistence(timeout: UITestID.timeout))
        let save = app.buttons[UITestID.nameEditorSave]
        XCTAssertTrue(save.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(save.isEnabled)

        // 入力欄は開いたときにキーボードの入力先になっている（カーソルは末尾）
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: UITestID.timeout))
        field.clearText()
        field.typeText("ゆい")
        XCTAssertTrue(field.waitForValue("ゆい"), field.value as? String ?? "")
        XCTAssertTrue(save.waitForEnabled())
        save.tap()

        // 保存するとシートが閉じ、行の名前が変わる
        let renamedRow = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", UITestID.displayNameRow, "ゆい")
        ).firstMatch
        XCTAssertTrue(field.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(renamedRow.waitForExistence(timeout: UITestID.timeout))

        // ホームに戻ってから開き直しても、新しい名前のまま
        app.buttons["戻る"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: UITestID.timeout))
        gear.tap()
        XCTAssertTrue(renamedRow.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(row.label.contains("たくみ"))
    }
}
