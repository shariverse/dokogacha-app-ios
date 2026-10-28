//
//  RoomUITests.swift
//  DokogachaUITests
//

import XCTest

/// ルーム（S-07）と候補（S-08〜S-10）の UI テスト。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす
final class RoomUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// ホームからルーム（S-07）を開き、ほかの人の候補のいいねを押すと「N人がいいね」の数が増え、ボタンが「いいね済」になる。
    /// 自分の投稿のいいねボタンは押せない（F-20 の AC）
    @MainActor
    func testLikeCandidateInRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        // 自分の投稿（江の島）のいいねボタンは押せない
        let mine = app.otherElements[UITestID.candidateCard(UITestID.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: UITestID.timeout))
        XCTAssertFalse(mine.buttons["自分の投稿にはいいねできません"].isEnabled)

        // そうたの投稿（明治神宮）はまだいいねが無い
        let shrine = app.otherElements[UITestID.candidateCard(UITestID.shrineCandidateID)]
        XCTAssertTrue(shrine.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(shrine.staticTexts["まだいいねはありません"].waitForExistence(timeout: UITestID.timeout))
        let like = shrine.buttons["いいね"]
        // ルームパネルの下に準備OKのボタンがあるので、ボタンが下部の「ガチャを回す」の帯より上に来るまで少しずつ送る
        let gachaBar = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(like.scrollIntoView(in: app, above: gachaBar))
        like.tap()

        XCTAssertTrue(shrine.staticTexts["1人がいいね"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(shrine.buttons["いいねを取り消す"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(shrine.staticTexts["まだいいねはありません"].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// ルーム（S-07）の自分の候補を押すと候補の詳細（S-10）がシートで開き、「この候補を削除」→ 確認の「削除する」で
    /// シートが閉じて S-07 に戻り、一覧からその候補が消える（F-11 の AC）
    @MainActor
    func testDeleteOwnCandidateFromDetail() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        // 自分の投稿（江の島）を開く
        let mine = app.otherElements[UITestID.candidateCard(UITestID.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: UITestID.timeout))
        // 候補の情報の列は VoiceOver で 1 つのボタンとして読む（`DGCandidateCard` の `OpenableDetails`）
        mine.buttons.matching(NSPredicate(format: "label CONTAINS %@", "江の島")).firstMatch.tap()
        let detail = app.otherElements[UITestID.candidateDetailScreen]
        XCTAssertTrue(detail.waitForExistence(timeout: UITestID.timeout))

        let delete = app.buttons[UITestID.candidateDetailDelete]
        XCTAssertTrue(delete.scrollIntoView(in: app))
        delete.tap()

        // 確認のダイアログで「削除する」を押す
        let confirm = app.buttons["削除する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()

        // シートが閉じて S-07 に戻り、候補が消える
        XCTAssertTrue(detail.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(mine.waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.candidateCard(UITestID.shrineCandidateID)].waitForExistence(timeout: UITestID.timeout))
    }

    /// ルーム（S-07）の「候補を追加」から S-08 を開き、検索して結果の「追加」を押すと S-09 が出て、
    /// ひとことを入れて「候補に追加」を押すと S-07 に戻り、候補が増えている（F-10。擬似の検索と擬似のサーバー）
    @MainActor
    func testAddCandidateFromSearch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let addButton = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()

        // S-08: 検索欄に入れると、少し待って結果が出る。自分の投稿は 0/3
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts[UITestID.addCandidatePostCount].waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(app.staticTexts[UITestID.addCandidatePostCount].label, "あなたの投稿 0/3件")
        let search = app.textFields[UITestID.addCandidateSearch]
        XCTAssertTrue(search.waitForExistence(timeout: UITestID.timeout))
        search.tap()
        search.typeText("水族館")
        let add = app.buttons[UITestID.sumidaAquariumAdd]
        XCTAssertTrue(add.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(add.label, "追加")
        add.tap()

        // S-09: 場所名と自動判定のカテゴリが出ている。ひとことを入れて投稿する
        let sheet = app.otherElements[UITestID.postCandidateScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        // 場所名は VoiceOver 用にエリアとまとめた要素にも同じ ID が付くので、最初のものを見る
        XCTAssertTrue(sheet.staticTexts[UITestID.postCandidatePlaceName].firstMatch.label.contains("すみだ水族館"))
        XCTAssertEqual(sheet.buttons[UITestID.postCandidateCategory].value as? String, "水族館")
        let note = sheet.textFields[UITestID.postCandidateNote]
        note.tap()
        note.typeText("クラゲが見たい")
        sheet.buttons[UITestID.postCandidateSubmit].tap()

        // S-07 に戻り、投稿した候補が一覧に増えている
        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(room.staticTexts["すみだ水族館"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(room.staticTexts["クラゲが見たい"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.otherElements[UITestID.postCandidateScreen].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// S-08 でエリアを北海道にすると、関東の場所は見つからず「北海道では見つかりませんでした」と「全国で探す」が出る。
    /// S-08 を開き直しても北海道のまま（選んだエリアを覚える）で、「全国で探す」で全国に戻して検索し直す（Issue #131）
    @MainActor
    func testSearchAreaNarrowsAndFallsBackToNationwide() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let addButton = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()

        // 初めは全国。検索すると関東の水族館が出る
        let nationwide = app.buttons[UITestID.addCandidateArea("nationwide")]
        let hokkaido = app.buttons[UITestID.addCandidateArea("hokkaido")]
        XCTAssertTrue(nationwide.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(nationwide.isSelected)
        let search = app.textFields[UITestID.addCandidateSearch]
        search.tap()
        search.typeText("水族館")
        XCTAssertTrue(app.buttons[UITestID.sumidaAquariumAdd].waitForExistence(timeout: UITestID.timeout))

        // 北海道にすると、待たずに検索し直して 0 件になる
        hokkaido.tap()
        let noResults = app.staticTexts[UITestID.addCandidateNoResults]
        XCTAssertTrue(noResults.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(noResults.label, "北海道では見つかりませんでした")
        XCTAssertTrue(app.buttons[UITestID.sumidaAquariumAdd].waitForNonExistence(timeout: UITestID.timeout))

        // 開き直しても北海道のまま
        app.buttons["戻る"].firstMatch.tap()
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()
        XCTAssertTrue(hokkaido.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(hokkaido.isSelected)
        XCTAssertFalse(nationwide.isSelected)
        search.tap()
        search.typeText("水族館")
        XCTAssertTrue(noResults.waitForExistence(timeout: UITestID.timeout))

        // 「全国で探す」で全国に戻して検索し直す
        app.buttons[UITestID.addCandidateSearchNationwide].tap()
        XCTAssertTrue(app.buttons[UITestID.sumidaAquariumAdd].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(nationwide.isSelected)
        XCTAssertFalse(hokkaido.isSelected)
    }

    /// ルーム（S-07）で「準備OK」を押すと人数とヒントが変わり、ボタンが「準備OKを取り消す」になる（F-30）。
    /// 作成者が「強制解禁（作成者）」→ 確認の「解禁する」を押すと「作成者が解禁しました」になり、ガチャを回せる（F-32）
    @MainActor
    func testReadyAndForceUnlockInRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[UITestID.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout))

        let readyCount = app.staticTexts[UITestID.roomReadyCount]
        XCTAssertTrue(readyCount.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(readyCount.label, "準備OK 0/4人")
        let hint = app.staticTexts[UITestID.roomReadyHint]
        XCTAssertEqual(hint.label, "全員OKで解禁 · あと 4人")
        XCTAssertFalse(app.buttons[UITestID.roomGacha].isEnabled)

        // 準備OK
        let ready = app.buttons[UITestID.roomReady]
        XCTAssertEqual(ready.label, "準備OK")
        ready.tap()
        XCTAssertTrue(app.staticTexts["準備OK 1/4人"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(hint.label, "全員OKで解禁 · あと 3人")
        XCTAssertEqual(ready.label, "準備OKを取り消す")

        // 強制解禁
        app.buttons[UITestID.roomForceUnlock].tap()
        let confirm = app.buttons["解禁する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["作成者が解禁しました。いつでも回せます"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.staticTexts["ガチャ解禁！"].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomForceUnlock].waitForNonExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[UITestID.roomGacha].isEnabled)
        XCTAssertEqual(app.buttons[UITestID.roomGacha].label, "ガチャを回す")
    }
}
