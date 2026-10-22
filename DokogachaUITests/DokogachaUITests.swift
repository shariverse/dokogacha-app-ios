//
//  DokogachaUITests.swift
//  DokogachaUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

/// 起動の流れ（F-01）とホーム（S-02）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす
final class DokogachaUITests: XCTestCase {
    /// S-01 の表示名の入力欄（`OnboardingView.Identifier.displayName`）
    private static let displayNameField = "onboarding.displayName"
    /// S-01 の「はじめる」（`OnboardingView.Identifier.start`）
    private static let startButton = "onboarding.start"
    /// ホーム（`HomeView.Identifier.screen`）
    private static let home = "home.screen"
    /// ホームのデモのルームのカード（`HomeView.Identifier.room(DemoScenario.roomID)`）
    private static let demoRoomCard = "home.room.demo-room"
    /// 進行中のルームの空の表示（`HomeView.Identifier.roomsEmpty`）
    private static let roomsEmpty = "home.rooms.empty"
    /// ルーム画面の仮の画面（`PendingScreenView.Identifier.screen(.room)`）
    private static let pendingRoom = "pending.room"
    /// ホームの「＋ ルームを作る」（`HomeView.Identifier.createRoom`）
    private static let createRoomButton = "home.createRoom"
    /// S-03（`CreateRoomView.Identifier.screen`）
    private static let createRoomScreen = "createRoom.screen"
    /// S-03 のルーム名の入力欄（`CreateRoomView.Identifier.name`）
    private static let roomNameField = "createRoom.name"
    /// S-03 の「ルームを作成」（`CreateRoomView.Identifier.submit`）
    private static let createRoomSubmit = "createRoom.submit"
    /// S-04（`InviteView.Identifier.screen`）
    private static let inviteScreen = "invite.screen"
    /// S-04 の招待コード（`InviteView.Identifier.code`）
    private static let inviteCode = "invite.code"
    /// S-04 の「ルームへ進む」（`InviteView.Identifier.openRoom`）
    private static let openRoomButton = "invite.openRoom"
    /// ホームの設定の歯車（`HomeView.Identifier.settings`）
    private static let settingsButton = "home.settings"
    /// S-15 設定（`SettingsView.Identifier.screen`）
    private static let settingsScreen = "settings.screen"
    /// S-15 の表示名の行（`SettingsView.Identifier.displayName`）
    private static let displayNameRow = "settings.displayName"
    /// 表示名の変更のシートの入力欄（`DisplayNameEditor.Identifier.field`）
    private static let nameEditorField = "settings.nameEditor.field"
    /// 表示名の変更のシートの「保存」（`DisplayNameEditor.Identifier.save`）
    private static let nameEditorSave = "settings.nameEditor.save"
    /// 画面が出るのを待つ時間
    private static let timeout: TimeInterval = 10

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

        let field = app.textFields[Self.displayNameField]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        let start = app.buttons[Self.startButton]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout))
        // 入力が空のときは押せない
        XCTAssertFalse(start.isEnabled)

        field.tap()
        field.typeText("ゆい")
        XCTAssertTrue(start.isEnabled)
        start.tap()

        XCTAssertTrue(app.otherElements[Self.home].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(field.exists)
    }

    /// 表示名を登録済み（2 回目の起動）では、S-01 を出さずにホームが開く
    @MainActor
    func testRegisteredUserSkipsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "empty"]
        app.launch()

        XCTAssertTrue(app.otherElements[Self.home].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.textFields[Self.displayNameField].exists)
        // ルームが無いので、進行中のルームは空の表示
        XCTAssertTrue(app.staticTexts[Self.roomsEmpty].waitForExistence(timeout: Self.timeout))
    }

    /// 進行中のルームがあればホームにカードが並び、押すとルーム画面（いまは仮の画面）へ進み、戻るとホームに戻る
    @MainActor
    func testHomeListsRoomAndOpensRoomScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(card.label.contains("年末の旅行"))
        XCTAssertFalse(app.staticTexts[Self.roomsEmpty].exists)

        card.tap()
        XCTAssertTrue(app.otherElements[Self.pendingRoom].waitForExistence(timeout: Self.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
    }

    /// ホームから「ルームを作る」→ 名前を入れて「ルームを作成」→ 招待の画面に招待コードが出る。
    /// 「ルームへ進む」でルーム画面（いまは仮の画面）に出て、戻るとホームに戻る（S-03 には戻らない。03 の §1）
    @MainActor
    func testCreateRoomShowsInviteCode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "empty"]
        app.launch()

        let createRoom = app.buttons[Self.createRoomButton]
        XCTAssertTrue(createRoom.waitForExistence(timeout: Self.timeout))
        createRoom.tap()

        let name = app.textFields[Self.roomNameField]
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout))
        let submit = app.buttons[Self.createRoomSubmit]
        XCTAssertTrue(submit.waitForExistence(timeout: Self.timeout))
        // ルーム名が空のときは押せない（F-02 の AC）
        XCTAssertFalse(submit.isEnabled)

        name.tap()
        name.typeText("年末の旅行")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(app.otherElements[Self.inviteScreen].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["年末の旅行"].exists)
        let code = app.buttons[Self.inviteCode]
        XCTAssertTrue(code.waitForExistence(timeout: Self.timeout))
        // 招待コードは 3 文字ずつハイフンで区切って出す（`0 O 1 I` は使わない）
        let pattern = "[A-HJ-NP-Z2-9]{3}-[A-HJ-NP-Z2-9]{3}"
        XCTAssertNotNil(code.label.range(of: pattern, options: .regularExpression), code.label)

        app.buttons[Self.openRoomButton].tap()
        XCTAssertTrue(app.otherElements[Self.pendingRoom].waitForExistence(timeout: Self.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[Self.home].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.otherElements[Self.createRoomScreen].exists)
        // 作ったルームがホームに並ぶ
        XCTAssertFalse(app.staticTexts[Self.roomsEmpty].exists)
    }

    /// ナビゲーションバーを隠した画面でも、画面の左端からのスワイプで戻れる（`InteractivePopGesture`）
    @MainActor
    func testEdgeSwipeGoesBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[Self.pendingRoom].waitForExistence(timeout: Self.timeout))

        swipeFromLeftEdge(app)
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.otherElements[Self.pendingRoom].exists)
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

        let gear = app.buttons[Self.settingsButton]
        XCTAssertTrue(gear.waitForExistence(timeout: Self.timeout))
        gear.tap()
        XCTAssertTrue(app.otherElements[Self.settingsScreen].waitForExistence(timeout: Self.timeout))

        // 今の名前が届いたら行に出る
        let row = app.buttons[Self.displayNameRow]
        let currentRow = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", Self.displayNameRow, "たくみ")
        ).firstMatch
        XCTAssertTrue(currentRow.waitForExistence(timeout: Self.timeout))
        row.tap()

        // シートは今の名前を入れて開き、同じ名前のままでは保存できない
        let field = app.textFields[Self.nameEditorField]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        let save = app.buttons[Self.nameEditorSave]
        XCTAssertTrue(save.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(save.isEnabled)

        // 入力欄は開いたときにキーボードの入力先になっている（カーソルは末尾）
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.timeout))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "ゆい")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // 保存するとシートが閉じ、行の名前が変わる
        let renamedRow = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", Self.displayNameRow, "ゆい")
        ).firstMatch
        XCTAssertTrue(field.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(renamedRow.waitForExistence(timeout: Self.timeout))

        // ホームに戻ってから開き直しても、新しい名前のまま
        app.buttons["戻る"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: Self.timeout))
        gear.tap()
        XCTAssertTrue(renamedRow.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(row.label.contains("たくみ"))
    }
}
