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
}
