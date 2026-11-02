//
//  PlaceMapUITests.swift
//  DokogachaUITests
//

import XCTest

/// S-17 場所の地図の UI テスト（Discussion #193。S-09 と S-10 から開く）。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす。
/// UI テストでは地図のタイルを読まない（地図の場所は同じ大きさの面）ので、地図以外の部品と、地図のボタンの ID・ラベルで確かめる
final class PlaceMapUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// S-09 の小さな地図を押すと、シートの中で S-17 へ進み、場所名のヘッダー・場所のカード・「元の位置に戻す」が出る。
    /// 「戻る」で S-09 に戻ると、入れたひとこと・参考 URL と選び直したカテゴリが残っている
    @MainActor
    func testOpenPlaceMapFromPostCandidateAndGoBack() throws {
        let app = launchToPostCandidate()
        let sheet = app.otherElements[UITestID.postCandidateScreen]

        // シートをラージに広げてから（ミディアムでは画面の真ん中がシートの外になるため）、カテゴリを街歩きに選び直し
        // （キーボードを出す前に選ぶ）、ひとことと参考 URL を入れておく。押す要素は tap() が見える位置まで送る
        sheet.swipeUp()
        sheet.buttons[UITestID.postCandidateCategory].tap()
        let town = sheet.buttons["postCandidate.category.town"]
        XCTAssertTrue(town.waitForExistence(timeout: UITestID.timeout))
        town.tap()
        XCTAssertTrue(sheet.buttons[UITestID.postCandidateCategory].waitForValue("街歩き"))
        let note = sheet.textFields[UITestID.postCandidateNote]
        note.tap()
        note.typeText("クラゲが見たい")
        let url = sheet.textFields[UITestID.postCandidateURL]
        url.tap()
        url.typeText("https://example.com/kurage")

        // 地図のボタン（VoiceOver のラベル付き）を押すと S-17 へ進む
        let mapButton = sheet.buttons[UITestID.postCandidateMap]
        XCTAssertTrue(mapButton.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(mapButton.label, "すみだ水族館の地図を開く")
        mapButton.tap()

        let placeMap = app.otherElements[UITestID.placeMapScreen]
        XCTAssertTrue(placeMap.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(placeMap.staticTexts["すみだ水族館"].firstMatch.exists)
        XCTAssertEqual(placeMap.descendants(matching: .any)[UITestID.placeMapMap].label, "すみだ水族館の地図")
        XCTAssertTrue(placeMap.descendants(matching: .any)[UITestID.placeMapCard].label.contains("街歩き"))
        XCTAssertTrue(placeMap.buttons[UITestID.placeMapRecenter].exists)
        // アプリの外（Apple のマップ）へ移るボタンは無い
        XCTAssertFalse(placeMap.buttons["マップで開く"].exists)

        // 「戻る」で S-09 に戻ると、入れたものが残っている
        placeMap.buttons["戻る"].tap()
        XCTAssertTrue(placeMap.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(sheet.textFields[UITestID.postCandidateNote].value as? String, "クラゲが見たい")
        XCTAssertEqual(sheet.textFields[UITestID.postCandidateURL].value as? String, "https://example.com/kurage")
        XCTAssertEqual(sheet.buttons[UITestID.postCandidateCategory].value as? String, "街歩き")
        XCTAssertTrue(sheet.buttons[UITestID.postCandidateSubmit].isEnabled)
    }

    /// S-17 から、画面の左端からのスワイプでも S-09 に戻れる（シートの中のスタックでもナビゲーションバーを隠しているため）
    @MainActor
    func testSwipeBackFromPlaceMapToPostCandidate() throws {
        let app = launchToPostCandidate()
        let sheet = app.otherElements[UITestID.postCandidateScreen]
        sheet.buttons[UITestID.postCandidateMap].tap()
        let placeMap = app.otherElements[UITestID.placeMapScreen]
        XCTAssertTrue(placeMap.waitForExistence(timeout: UITestID.timeout))

        swipeFromLeftEdge(of: placeMap)

        XCTAssertTrue(placeMap.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.buttons[UITestID.postCandidateMap].waitForExistence(timeout: UITestID.timeout))
    }

    /// S-10 候補の詳細の地図を押すと、シートの中で S-17 へ進む。S-17 には「マップで開く」は無く、「戻る」・端からのスワイプで S-10 に戻る。
    /// S-10 の「マップで開く」（Apple のマップへ）は残っている
    @MainActor
    func testOpenPlaceMapFromCandidateDetailAndGoBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        // 自分の投稿（江の島）の詳細を開く（候補の情報の列は VoiceOver で 1 つのボタンとして読む）
        let mine = app.otherElements[UITestID.candidateCard(UITestID.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: UITestID.timeout))
        mine.buttons.matching(NSPredicate(format: "label CONTAINS %@", "江の島")).firstMatch.tap()
        let detail = app.otherElements[UITestID.candidateDetailScreen]
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.candidateDetailOpenInMaps].waitForExistence(timeout: UITestID.timeout))

        let mapButton = app.buttons[UITestID.candidateDetailMap]
        XCTAssertTrue(mapButton.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(mapButton.label, "江の島の地図を開く")
        mapButton.tap()

        let placeMap = app.otherElements[UITestID.placeMapScreen]
        XCTAssertTrue(placeMap.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(placeMap.staticTexts["江の島"].firstMatch.exists)
        XCTAssertTrue(placeMap.buttons[UITestID.placeMapRecenter].exists)
        XCTAssertFalse(placeMap.buttons["マップで開く"].exists)

        // 「戻る」で S-10 に戻る
        placeMap.buttons["戻る"].tap()
        XCTAssertTrue(placeMap.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(mapButton.waitForExistence(timeout: UITestID.timeout))

        // もう一度開き、端からのスワイプでも S-10 に戻る
        mapButton.tap()
        XCTAssertTrue(placeMap.waitForExistence(timeout: UITestID.timeout))
        swipeFromLeftEdge(of: placeMap)
        XCTAssertTrue(placeMap.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))
    }

    /// S-10 の上に S-17 を積んだまま、シートを下へのスワイプで閉じると S-07 に戻る。同じ候補を開き直すと、
    /// S-17 を残さずに S-10 から始まる（購読・閉じる判定はスタックの外で持つので、S-17 を積んでいても閉じられる）
    @MainActor
    func testDismissCandidateDetailSheetWhilePlaceMapIsStacked() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        let mine = app.otherElements[UITestID.candidateCard(UITestID.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: UITestID.timeout))
        mine.buttons.matching(NSPredicate(format: "label CONTAINS %@", "江の島")).firstMatch.tap()
        let detail = app.otherElements[UITestID.candidateDetailScreen]
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))
        app.buttons[UITestID.candidateDetailMap].tap()
        let placeMap = app.otherElements[UITestID.placeMapScreen]
        XCTAssertTrue(placeMap.waitForExistence(timeout: UITestID.timeout))

        // S-17 のヘッダーのあたりから下へスワイプして、シートごと閉じる
        let top = placeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.05, thenDragTo: bottom)
        XCTAssertTrue(placeMap.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(detail.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))

        // 開き直すと S-10 から始まる
        mine.buttons.matching(NSPredicate(format: "label CONTAINS %@", "江の島")).firstMatch.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.candidateDetailMap].waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(placeMap.exists)
    }

    /// 画面（シート）の左端から右へスワイプする（端からの戻る操作）。iPad の中央に出るシートでも届くよう、画面ではなく要素の左端から動かす
    @MainActor
    private func swipeFromLeftEdge(of element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// ルーム（S-07）の「候補を追加」から S-08 で「水族館」を検索し、すみだ水族館の「追加」で S-09 を出す
    @MainActor
    private func launchToPostCandidate() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let addButton = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()
        let search = app.textFields[UITestID.addCandidateSearch]
        XCTAssertTrue(search.waitForExistence(timeout: UITestID.timeout))
        search.tap()
        search.typeText("水族館")
        let add = app.buttons[UITestID.sumidaAquariumAdd]
        XCTAssertTrue(add.waitForExistence(timeout: UITestID.timeout))
        add.tap()
        XCTAssertTrue(app.otherElements[UITestID.postCandidateScreen].waitForExistence(timeout: UITestID.timeout))
        return app
    }
}
