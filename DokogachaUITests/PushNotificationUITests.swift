//
//  PushNotificationUITests.swift
//  DokogachaUITests
//

import XCTest

/// プッシュ通知（02 の §8 F-60）を開いたときの UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす。
///
/// 擬似のサーバーでは通知が届かない（`-uiTesting` では通知の許可も尋ねない）ので、起動引数 `-open-notification <ペイロードの JSON>` で
/// 起動の直後に通知を開いたことにする（アプリは `UNUserNotificationCenterDelegate` で開いたときと同じ `DeepLinkRouter` に渡す）
final class PushNotificationUITests: XCTestCase {
    /// 解禁の通知のペイロード（backend の `pushData` と同じ形。`several-rooms` の解禁済みのルーム）
    private static let unlockedPayload = #"{"type":"unlocked","roomId":"demo-room-unlocked","target":"room"}"#
    /// ホームの解禁済みのルームのカード
    private static let unlockedRoomCard = "home.room.demo-room-unlocked"

    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 起動していないときに解禁の通知を開くと、ホームの上にそのルーム（S-07）が開き、戻るとホームに出る
    @MainActor
    func testOpeningUnlockedNotificationOpensRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "several-rooms", "-open-notification", Self.unlockedPayload]
        app.launch()

        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        // 解禁済みのルームなので「ガチャを回す」が出ている
        let gachaButton = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gachaButton.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(gachaButton.label, "ガチャを回す")

        app.buttons["戻る"].tap()
        XCTAssertTrue(app.buttons[Self.unlockedRoomCard].waitForExistence(timeout: UITestID.timeout))
    }
}
