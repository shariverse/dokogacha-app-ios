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
    /// S-07 ルーム（`RoomView.Identifier.screen`）
    private static let roomScreen = "room.screen"
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
    /// ホームの「招待コードで参加」（`HomeView.Identifier.joinByCode`）
    private static let joinByCodeButton = "home.joinByCode"
    /// S-05 の招待コードの入力欄（`JoinByCodeView.Identifier.code`）
    private static let joinCodeField = "joinByCode.code"
    /// S-05 の入力欄の下のエラー（`JoinByCodeView.Identifier.error`）
    private static let joinCodeError = "joinByCode.error"
    /// S-05 の「参加する」（`JoinByCodeView.Identifier.submit`）
    private static let joinCodeSubmit = "joinByCode.submit"
    /// S-06（`JoinConfirmView.Identifier.screen`）
    private static let joinConfirmScreen = "joinConfirm.screen"
    /// S-06 のルームのカード（`JoinConfirmView.Identifier.card`）
    private static let joinConfirmCard = "joinConfirm.card"
    /// S-06 の「参加する」（`JoinConfirmView.Identifier.join`）
    private static let joinConfirmJoin = "joinConfirm.join"
    /// デモの参加できるルームの ID（`DemoScenario.joinableRoomID`）
    private static let joinableRoomID = "demo-room-joinable"
    /// デモの自分の候補（`room-with-candidates` の江の島）
    private static let myCandidateID = "demo-candidate-3"
    /// デモのそうたの候補（`room-with-candidates` の明治神宮。いいね 0）
    private static let shrineCandidateID = "demo-candidate-2"
    /// S-10 候補の詳細（`CandidateDetailView.Identifier.screen`）
    private static let candidateDetailScreen = "candidateDetail.screen"
    /// S-10 の「この候補を削除」（`CandidateDetailView.Identifier.delete`）
    private static let candidateDetailDelete = "candidateDetail.delete"
    /// S-07 の見出し行の「候補を追加」（`RoomView.Identifier.addCandidate`）
    private static let roomAddCandidate = "room.addCandidate"
    /// S-08（`AddCandidateView.Identifier.screen`）
    private static let addCandidateScreen = "addCandidate.screen"
    /// S-08 のヘッダーの「n/上限」（`AddCandidateView.Identifier.postCount`）
    private static let addCandidatePostCount = "addCandidate.postCount"
    /// S-08 の検索欄（`AddCandidateView.Identifier.searchField`）
    private static let addCandidateSearch = "addCandidate.search"
    /// S-08 のすみだ水族館の「追加」（`AddCandidateView.Identifier.add(DemoPlaceSearchService.sumidaAquariumID)`）
    private static let sumidaAquariumAdd = "addCandidate.place.demo-place-sumida-aquarium.add"
    /// S-09（`PostCandidateView.Identifier.screen`）
    private static let postCandidateScreen = "postCandidate.screen"
    /// S-09 の場所名（`PostCandidateView.Identifier.placeName`）
    private static let postCandidatePlaceName = "postCandidate.placeName"
    /// S-09 のカテゴリ（`PostCandidateView.Identifier.category`）
    private static let postCandidateCategory = "postCandidate.category"
    /// S-09 のひとこと（`PostCandidateView.Identifier.note`）
    private static let postCandidateNote = "postCandidate.note"
    /// S-09 の「候補に追加」（`PostCandidateView.Identifier.submit`）
    private static let postCandidateSubmit = "postCandidate.submit"
    /// S-07 の「準備OK n/m」（`RoomView.Identifier.readyCount`）
    private static let roomReadyCount = "room.readyCount"
    /// S-07 のヒント文言（`RoomView.Identifier.readyHint`）
    private static let roomReadyHint = "room.readyHint"
    /// S-07 の「準備OK」「準備OKを取り消す」（`RoomView.Identifier.ready`）
    private static let roomReady = "room.ready"
    /// S-07 の「強制解禁（作成者）」（`RoomView.Identifier.forceUnlock`）
    private static let roomForceUnlock = "room.forceUnlock"
    /// S-07 の下部の「ガチャを回す」（`RoomView.Identifier.gacha`）
    private static let roomGacha = "room.gacha"
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

    /// 進行中のルームがあればホームにカードが並び、押すとルーム画面へ進み、戻るとホームに戻る
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
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
    }

    /// ホームから「ルームを作る」→ 名前を入れて「ルームを作成」→ 招待の画面に招待コードが出る。
    /// 「ルームへ進む」でルーム画面に出て、戻るとホームに戻る（S-03 には戻らない。03 の §1）
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
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[Self.home].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.otherElements[Self.createRoomScreen].exists)
        // 作ったルームがホームに並ぶ
        XCTAssertFalse(app.staticTexts[Self.roomsEmpty].exists)
    }

    /// ホームから「招待コードで参加」→ 存在しないコードでは入力欄の下にエラー → 正しいコード（小文字・ハイフンなし）を入れて
    /// 「参加する」→ S-06 にルーム名が出る → 「参加する」でシートが閉じてルーム画面が開く（F-04 の AC）。
    /// 戻るとホームに参加したルームが並ぶ
    @MainActor
    func testJoinRoomByInviteCode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "joinable"]
        app.launch()

        let joinByCode = app.buttons[Self.joinByCodeButton]
        XCTAssertTrue(joinByCode.waitForExistence(timeout: Self.timeout))
        joinByCode.tap()

        let field = app.textFields[Self.joinCodeField]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        let submit = app.buttons[Self.joinCodeSubmit]
        XCTAssertTrue(submit.waitForExistence(timeout: Self.timeout))
        // 6 文字を入れるまでは押せない
        XCTAssertFalse(submit.isEnabled)

        field.tap()
        field.typeText("zzzzzz")
        XCTAssertEqual(field.value as? String, "ZZZ-ZZZ")
        submit.tap()
        let error = app.staticTexts[Self.joinCodeError]
        XCTAssertTrue(error.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(error.label, "招待コードが見つかりません")

        // 入れ直す（全部消してから、デモの参加できるルームのコードを小文字・ハイフンなしで打つ）
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        field.typeText("qw58rt")
        XCTAssertEqual(field.value as? String, "QW5-8RT")
        XCTAssertFalse(error.exists)
        submit.tap()

        let card = app.descendants(matching: .any)[Self.joinConfirmCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.otherElements[Self.joinConfirmScreen].exists)
        XCTAssertTrue(card.label.contains("夏の花火大会"), card.label)
        XCTAssertTrue(card.label.contains("はるか"), card.label)
        app.buttons[Self.joinConfirmJoin].tap()

        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.otherElements[Self.joinConfirmScreen].exists)
        app.buttons["戻る"].tap()
        XCTAssertTrue(app.otherElements[Self.home].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["home.room.\(Self.joinableRoomID)"].waitForExistence(timeout: Self.timeout))
    }

    /// ホームからルーム（S-07）を開き、ほかの人の候補のいいねを押すと「N人がいいね」の数が増え、ボタンが「いいね済」になる。
    /// 自分の投稿のいいねボタンは押せない（F-20 の AC）
    @MainActor
    func testLikeCandidateInRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))

        // 自分の投稿（江の島）のいいねボタンは押せない
        let mine = app.otherElements[Self.candidateCard(Self.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(mine.buttons["自分の投稿にはいいねできません"].isEnabled)

        // そうたの投稿（明治神宮）はまだいいねが無い
        let shrine = app.otherElements[Self.candidateCard(Self.shrineCandidateID)]
        XCTAssertTrue(shrine.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(shrine.staticTexts["まだいいねはありません"].exists)
        let like = shrine.buttons["いいね"]
        // ルームパネルの下に準備OKのボタンがあるので、ボタンが下部の「ガチャを回す」の帯より上に来るまで少しずつ送る
        let gachaBar = app.buttons[Self.roomGacha]
        for _ in 0..<5 where !like.isHittable || like.frame.maxY > gachaBar.frame.minY {
            app.swipeUp(velocity: .slow)
        }
        like.tap()

        XCTAssertTrue(shrine.staticTexts["1人がいいね"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(shrine.buttons["いいねを取り消す"].exists)
        XCTAssertFalse(shrine.staticTexts["まだいいねはありません"].exists)
    }

    /// ルーム（S-07）の自分の候補を押すと候補の詳細（S-10）がシートで開き、「この候補を削除」→ 確認の「削除する」で
    /// シートが閉じて S-07 に戻り、一覧からその候補が消える（F-11 の AC）
    @MainActor
    func testDeleteOwnCandidateFromDetail() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))

        // 自分の投稿（江の島）を開く
        let mine = app.otherElements[Self.candidateCard(Self.myCandidateID)]
        XCTAssertTrue(mine.waitForExistence(timeout: Self.timeout))
        // 候補の情報の列は VoiceOver で 1 つのボタンとして読む（`DGCandidateCard` の `OpenableDetails`）
        mine.buttons.matching(NSPredicate(format: "label CONTAINS %@", "江の島")).firstMatch.tap()
        let detail = app.otherElements[Self.candidateDetailScreen]
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))

        let delete = app.buttons[Self.candidateDetailDelete]
        if !delete.waitForExistence(timeout: Self.timeout) || !delete.isHittable {
            detail.swipeUp()
        }
        XCTAssertTrue(delete.isHittable)
        delete.tap()

        // 確認のダイアログで「削除する」を押す
        let confirm = app.buttons["削除する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout))
        confirm.tap()

        // シートが閉じて S-07 に戻り、候補が消える
        XCTAssertTrue(detail.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(app.otherElements[Self.roomScreen].exists)
        XCTAssertTrue(mine.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(app.otherElements[Self.candidateCard(Self.shrineCandidateID)].exists)
    }

    /// ルーム（S-07）の「候補を追加」から S-08 を開き、検索して結果の「追加」を押すと S-09 が出て、
    /// ひとことを入れて「候補に追加」を押すと S-07 に戻り、候補が増えている（F-10。擬似の検索と擬似のサーバー）
    @MainActor
    func testAddCandidateFromSearch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "one-room"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.tap()
        let addButton = app.buttons[Self.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: Self.timeout))
        addButton.tap()

        // S-08: 検索欄に入れると、少し待って結果が出る。自分の投稿は 0/3
        XCTAssertTrue(app.otherElements[Self.addCandidateScreen].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts[Self.addCandidatePostCount].waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(app.staticTexts[Self.addCandidatePostCount].label, "あなたの投稿 0/3件")
        let search = app.textFields[Self.addCandidateSearch]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout))
        search.tap()
        search.typeText("水族館")
        let add = app.buttons[Self.sumidaAquariumAdd]
        XCTAssertTrue(add.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(add.label, "追加")
        add.tap()

        // S-09: 場所名と自動判定のカテゴリが出ている。ひとことを入れて投稿する
        let sheet = app.otherElements[Self.postCandidateScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: Self.timeout))
        // 場所名は VoiceOver 用にエリアとまとめた要素にも同じ ID が付くので、最初のものを見る
        XCTAssertTrue(sheet.staticTexts[Self.postCandidatePlaceName].firstMatch.label.contains("すみだ水族館"))
        XCTAssertEqual(sheet.buttons[Self.postCandidateCategory].value as? String, "水族館")
        let note = sheet.textFields[Self.postCandidateNote]
        note.tap()
        note.typeText("クラゲが見たい")
        sheet.buttons[Self.postCandidateSubmit].tap()

        // S-07 に戻り、投稿した候補が一覧に増えている
        let room = app.otherElements[Self.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(room.staticTexts["すみだ水族館"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(room.staticTexts["クラゲが見たい"].exists)
        XCTAssertFalse(app.otherElements[Self.addCandidateScreen].exists)
        XCTAssertFalse(app.otherElements[Self.postCandidateScreen].exists)
    }

    /// ルーム（S-07）で「準備OK」を押すと人数とヒントが変わり、ボタンが「準備OKを取り消す」になる（F-30）。
    /// 作成者が「強制解禁（作成者）」→ 確認の「解禁する」を押すと「作成者が解禁しました」になり、ガチャを回せる（F-32）
    @MainActor
    func testReadyAndForceUnlockInRoom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", "room-with-candidates"]
        app.launch()

        let card = app.buttons[Self.demoRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))

        let readyCount = app.staticTexts[Self.roomReadyCount]
        XCTAssertTrue(readyCount.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(readyCount.label, "準備OK 0/4人")
        let hint = app.staticTexts[Self.roomReadyHint]
        XCTAssertEqual(hint.label, "全員OKで解禁 · あと 4人")
        XCTAssertFalse(app.buttons[Self.roomGacha].isEnabled)

        // 準備OK
        let ready = app.buttons[Self.roomReady]
        XCTAssertEqual(ready.label, "準備OK")
        ready.tap()
        XCTAssertTrue(app.staticTexts["準備OK 1/4人"].waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(hint.label, "全員OKで解禁 · あと 3人")
        XCTAssertEqual(ready.label, "準備OKを取り消す")

        // 強制解禁
        app.buttons[Self.roomForceUnlock].tap()
        let confirm = app.buttons["解禁する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["作成者が解禁しました。いつでも回せます"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["ガチャ解禁！"].exists)
        XCTAssertFalse(app.buttons[Self.roomForceUnlock].exists)
        XCTAssertTrue(app.buttons[Self.roomGacha].isEnabled)
        XCTAssertEqual(app.buttons[Self.roomGacha].label, "ガチャを回す")
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
        XCTAssertTrue(app.otherElements[Self.roomScreen].waitForExistence(timeout: Self.timeout))

        swipeFromLeftEdge(app)
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.otherElements[Self.roomScreen].exists)
    }

    /// S-07 の候補のカード（`RoomView.Identifier.candidate(_:)`）
    private static func candidateCard(_ candidateID: String) -> String {
        "room.candidate.\(candidateID)"
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
