//
//  ScenarioUITests.swift
//  DokogachaUITests
//

import XCTest

extension UITestID {
    /// ほかのメンバーの参加・準備OK・引き直しの賛成を擬似のサーバーが自動で返す起動引数（`LaunchContext.autoMembersArgument`）
    static let autoMembersArgument = "-ui-auto-members"
    /// S-14 の「過半数が賛成。もう一度引けます」（`ResultRerollSection.Identifier.passed`）
    static let resultRerollPassed = "result.reroll.passed"
    /// S-14 の可決の後の「ガチャを回す」（`ResultRerollSection.Identifier.playAgain`）
    static let resultRerollPlayAgain = "result.reroll.playAgain"
    /// S-14 の「この行き先で決定」（`ResultCloseSection.Identifier.decide`）
    static let resultDecide = "result.decide"
    /// S-13（`GachaView.Identifier.screen`）
    static let gachaScreen = "gacha.screen"
    /// S-07 の候補のカードの ID の前置き（後ろに候補の ID。作った候補の ID は乱数なので、前置きと文言で探す）
    static let candidateCardPrefix = "room.candidate."
    /// ホームの思い出のきっぷの ID の前置き（`HomeMemoryTickets.Identifier.ticket(_:)`。後ろにルームの ID）
    static let memoryTicketPrefix = "home.memory."
    /// `several-rooms` の解禁済みのルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.unlockedRoomID)`）
    static let unlockedRoomCard = "home.room.demo-room-unlocked"
    /// `drawn-rooms` の自分が作った行き先が決まったルーム（週末のランチ）のカード（`HomeView.Identifier.room(DemoScenario.drawnRoomID)`）
    static let myDrawnRoomCard = "home.room.demo-room-drawn-mine"
    /// S-08 の江の島の「追加」（`AddCandidateView.Identifier.add("demo-place-enoshima")`）
    static let enoshimaAdd = "addCandidate.place.demo-place-enoshima.add"
}

/// 06 の §2 の UI テストのシナリオ（通しの流れ）。メモリ上の擬似のサーバー（`-uiTesting -demo-scenario <名前>`）で動かす。
///
/// ほかのメンバーの参加・準備OK・引き直しの賛成は、起動引数 `-ui-auto-members` で擬似のサーバーが自動で返す（`InMemoryAutoMembers`）。
/// 本番の画面にはテストのための操作を足さない
final class ScenarioUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 06 の §2 の 1: 表示名の登録 → ルームの作成 → 招待コードで 2 人目（はるか）が参加して候補を投稿 → 自分が候補を 2 件投稿 →
    /// はるかの候補にいいね → 自分が準備OK（はるかも準備OKにして全員OKで解禁）→ ガチャ → 結果 → 決定 → ホームの「思い出のきっぷ」に出る
    @MainActor
    func testCreateRoomToDecisionShowsMemoryTicket() throws {
        let app = launch(scenario: "first-launch", autoMembers: true)

        // S-01: 表示名を登録してホームへ
        let nameField = app.textFields[UITestID.displayNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITestID.timeout))
        nameField.tap()
        nameField.typeText("たくみ")
        let start = app.buttons[UITestID.startButton]
        XCTAssertTrue(start.waitForEnabled())
        start.tap()
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout))

        // S-03 → S-04 → S-07: ルームを作る。はるかが招待コードで参加し、明治神宮を投稿する
        createRoom(app, name: "年末の旅行")
        let readyCount = app.staticTexts[UITestID.roomReadyCount]
        XCTAssertTrue(readyCount.waitForLabel("準備OK 0/2人"), readyCount.label)
        let harukasCandidate = candidateCard(app, containing: "明治神宮")
        XCTAssertTrue(harukasCandidate.waitForExistence(timeout: UITestID.timeout))

        // S-08 → S-09: 自分の候補を 2 件投稿する（合わせて 3 件）
        addCandidate(app, search: "水族館", addButton: UITestID.sumidaAquariumAdd, placeName: "すみだ水族館")
        addCandidate(app, search: "海", addButton: UITestID.enoshimaAdd, placeName: "江の島")

        // はるかの候補にいいね
        let like = harukasCandidate.buttons["いいね"]
        XCTAssertTrue(like.scrollIntoView(in: app, above: app.buttons[UITestID.roomGacha]))
        like.tap()
        XCTAssertTrue(harukasCandidate.staticTexts["1人がいいね"].waitForExistence(timeout: UITestID.timeout))

        // 自分が準備OK → はるかも準備OKにして、全員OKで解禁される
        let ready = app.buttons[UITestID.roomReady]
        XCTAssertTrue(ready.scrollIntoView(in: app, towardTop: true))
        XCTAssertEqual(ready.label, "準備OK")
        ready.tap()
        XCTAssertTrue(readyCount.waitForLabel("準備OK 2/2人"), readyCount.label)
        XCTAssertTrue(app.staticTexts["ガチャ解禁！"].waitForExistence(timeout: UITestID.timeout))

        // S-13 → S-14: ガチャを回して結果を出し、作成者として決定する
        let gacha = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gacha.waitForEnabled())
        gacha.tap()
        let winner = drawFromGachaScreen(app, roomName: "年末の旅行")
        decide(app)

        // ホーム: 進行中のルームから消え、思い出のきっぷに当選と外れた候補の数が出る
        let ticket = app.buttons.first(identifierPrefix: UITestID.memoryTicketPrefix, labelContaining: "年末の旅行")
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(ticket.label.contains(winner), ticket.label)
        XCTAssertTrue(ticket.label.contains("外れた候補 2件は次のルームで使えます"), ticket.label)
        XCTAssertTrue(app.staticTexts[UITestID.roomsEmpty].waitForExistence(timeout: UITestID.timeout))
    }

    /// 06 の §2 の 2: 結果（S-14）で引き直しを提案 → ほかのメンバーが賛成して可決 → 「ガチャを回す」でもう一度回すと、
    /// 前回の当選は対象から外れて別の行き先になり、引き直しは使用済みになる（F-43）
    @MainActor
    func testRerollPassedByOthersExcludesPreviousWinner() throws {
        let app = launch(scenario: "several-rooms", autoMembers: true)

        let card = app.buttons[UITestID.unlockedRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        let gacha = app.buttons[UITestID.roomGacha]
        XCTAssertTrue(gacha.waitForEnabled())
        gacha.tap()
        // 1 回目は候補 3 件がすべてカプセルになる（ドームの VoiceOver のラベル）
        XCTAssertTrue(app.descendants(matching: .any)["ガチャ。カプセル 3個"].waitForExistence(timeout: UITestID.timeout))
        let firstWinner = drawFromGachaScreen(app, roomName: "週末のランチ")

        // 提案すると自分が賛成し、はるか・そうたの賛成で過半数になって可決する
        let propose = app.buttons[UITestID.resultRerollPropose]
        XCTAssertTrue(propose.scrollIntoView(in: app))
        propose.tap()
        let passed = app.descendants(matching: .any)[UITestID.resultRerollPassed]
        XCTAssertTrue(passed.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(passed.label, "過半数が賛成。もう一度引けます")

        // 「ガチャを回す」で S-13 に戻って回し直すと、前回の当選とは別の行き先になる
        let playAgain = app.buttons[UITestID.resultRerollPlayAgain]
        XCTAssertTrue(playAgain.scrollIntoView(in: app))
        playAgain.tap()
        XCTAssertTrue(app.otherElements[UITestID.gachaScreen].waitForExistence(timeout: UITestID.timeout))
        // 前回の当選は対象から外れるので、カプセルが 1 つ減る（偶然別の候補を引いても通らないように、数でも確かめる。PR #103 の持ち越し）
        XCTAssertTrue(app.descendants(matching: .any)["ガチャ。カプセル 2個"].waitForExistence(timeout: UITestID.timeout))
        let secondWinner = drawFromGachaScreen(app, roomName: "週末のランチ")
        XCTAssertNotEqual(secondWinner, firstWinner)

        // 引き直しは 1 回まで
        let status = app.staticTexts[UITestID.resultRerollStatus]
        XCTAssertTrue(status.scrollIntoView(in: app))
        XCTAssertTrue(status.waitForLabel("引き直しは使用済みです"), status.label)
        XCTAssertTrue(app.buttons[UITestID.resultRerollPropose].waitForNonExistence(timeout: UITestID.timeout))
    }

    /// 06 の §2 の 3: 行き先が決まったルームを決定して終了 → 次のルームを作り、S-08 の「過去のアイデア」に
    /// 終了したルームの外れた候補（当選は出ない）が並び、「持ち込む」で新しいルームの候補になる（F-13・F-44）
    @MainActor
    func testBringLosingCandidateIntoNextRoom() throws {
        let app = launch(scenario: "drawn-rooms", autoMembers: false)

        // 行き先が決まったルーム（週末のランチ。サンシャイン水族館が当選）を決定して終了する
        let card = app.buttons[UITestID.myDrawnRoomCard]
        XCTAssertTrue(card.waitForExistence(timeout: UITestID.timeout))
        card.tap()
        XCTAssertTrue(app.otherElements[UITestID.resultScreen].waitForExistence(timeout: UITestID.timeout))
        decide(app)
        let memory = app.buttons.first(identifierPrefix: UITestID.memoryTicketPrefix, labelContaining: "週末のランチ")
        XCTAssertTrue(memory.waitForExistence(timeout: UITestID.timeout))

        // 次のルームを作り、S-08 の「過去のアイデア」を開く
        createRoom(app, name: "秋の遠足")
        let addButton = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(addButton.waitForExistence(timeout: UITestID.timeout))
        addButton.tap()
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForExistence(timeout: UITestID.timeout))
        let tab = app.buttons[UITestID.pastIdeasTab]
        XCTAssertTrue(tab.waitForExistence(timeout: UITestID.timeout))
        tab.tap()

        // 終了したルームの見出しの下に外れた候補（明治神宮・江の島）が並び、当選（サンシャイン水族館）は出ない
        let header = app.descendants(matching: .any)[Self.pastIdeaGroup]
        XCTAssertTrue(header.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(header.label.hasPrefix("週末のランチ、"), header.label)
        XCTAssertTrue(app.buttons[Self.pastIdeaBring("drawn-mine-3")].waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(app.buttons[Self.pastIdeaBring("drawn-mine-1")].waitForNonExistence(timeout: UITestID.timeout))
        let bring = app.buttons[Self.pastIdeaBring("drawn-mine-2")]
        XCTAssertTrue(bring.waitForExistence(timeout: UITestID.timeout))
        XCTAssertEqual(bring.label, "持ち込む")
        bring.tap()

        // S-09 に場所名と前回のカテゴリが出ている。そのまま投稿すると、新しいルームの候補になる
        let sheet = app.otherElements[UITestID.postCandidateScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.staticTexts[UITestID.postCandidatePlaceName].firstMatch.label.contains("明治神宮"))
        XCTAssertEqual(sheet.buttons[UITestID.postCandidateCategory].value as? String, "寺社")
        sheet.buttons[UITestID.postCandidateSubmit].tap()
        let room = app.otherElements[UITestID.roomScreen]
        XCTAssertTrue(room.waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(candidateCard(app, containing: "明治神宮").waitForExistence(timeout: UITestID.timeout))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout))
    }

    // MARK: - 手順

    /// `drawn-rooms` の週末のランチの、過去のアイデアの見出し（`PastIdeasSection.Identifier.group(DemoScenario.drawnRoomID)`）
    private static let pastIdeaGroup = "addCandidate.pastIdeas.group.demo-room-drawn-mine"

    /// 週末のランチの候補から作った過去のアイデアの「持ち込む」（`PastIdeasSection.Identifier.bring("<ルーム>_<候補>")`）
    private static func pastIdeaBring(_ candidateID: String) -> String {
        "addCandidate.pastIdea.demo-room-drawn-mine_\(candidateID).bring"
    }

    /// 擬似のサーバーのシナリオを選んで起動する
    @MainActor
    private func launch(scenario: String, autoMembers: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-demo-scenario", scenario]
        if autoMembers {
            app.launchArguments.append(UITestID.autoMembersArgument)
        }
        app.launch()
        return app
    }

    /// ホームから「ルームを作る」→ 名前を入れて作成 → S-04 の「ルームへ進む」で S-07 を開く
    @MainActor
    private func createRoom(_ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let createRoom = app.buttons[UITestID.createRoomButton]
        XCTAssertTrue(createRoom.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        createRoom.tap()
        let nameField = app.textFields[UITestID.roomNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        nameField.tap()
        nameField.typeText(name)
        let submit = app.buttons[UITestID.createRoomSubmit]
        XCTAssertTrue(submit.waitForEnabled(), file: file, line: line)
        submit.tap()
        XCTAssertTrue(app.otherElements[UITestID.inviteScreen].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(app.buttons[UITestID.inviteCode].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        app.buttons[UITestID.openRoomButton].tap()
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
    }

    /// S-07 の「候補を追加」→ S-08 で検索して結果の「追加」→ S-09 の「候補に追加」で S-07 に戻り、候補が並ぶ
    @MainActor
    private func addCandidate(
        _ app: XCUIApplication,
        search query: String,
        addButton: String,
        placeName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let open = app.buttons[UITestID.roomAddCandidate]
        XCTAssertTrue(open.scrollIntoView(in: app, towardTop: true), file: file, line: line)
        open.tap()
        XCTAssertTrue(app.otherElements[UITestID.addCandidateScreen].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        let search = app.textFields[UITestID.addCandidateSearch]
        XCTAssertTrue(search.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        search.tap()
        search.typeText(query)
        let add = app.buttons[addButton]
        XCTAssertTrue(add.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        add.tap()
        let sheet = app.otherElements[UITestID.postCandidateScreen]
        XCTAssertTrue(sheet.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        sheet.buttons[UITestID.postCandidateSubmit].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(app.otherElements[UITestID.roomScreen].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(candidateCard(app, containing: placeName).waitForExistence(timeout: UITestID.timeout), file: file, line: line)
    }

    /// S-13 でレバーを回し、S-14 の行き先きっぷを出す（カプセルは押さなくても開く）。当選した場所名を返す
    @MainActor
    private func drawFromGachaScreen(
        _ app: XCUIApplication,
        roomName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let lever = app.buttons["レバーを回す"]
        XCTAssertTrue(lever.waitForEnabled(), file: file, line: line)
        lever.tap()
        let result = app.otherElements[UITestID.resultScreen]
        XCTAssertTrue(result.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        let ticket = result.descendants(matching: .any)[UITestID.resultTicket]
        XCTAssertTrue(ticket.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        // きっぷのラベルは「行き先きっぷ、<ルーム名>。<場所名> ゆき。…」（`DGDestinationTicket`）
        let prefix = "行き先きっぷ、\(roomName)。"
        XCTAssertTrue(ticket.label.hasPrefix(prefix), ticket.label, file: file, line: line)
        let rest = ticket.label.dropFirst(prefix.count)
        let winner = rest.components(separatedBy: " ゆき。").first ?? ""
        XCTAssertFalse(winner.isEmpty, ticket.label, file: file, line: line)
        return winner
    }

    /// S-14 で作成者が「この行き先で決定」→ 確認の「決定する」で、ルームを終了してホームに戻る
    @MainActor
    private func decide(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let decide = app.buttons[UITestID.resultDecide]
        XCTAssertTrue(decide.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(decide.scrollIntoView(in: app), file: file, line: line)
        decide.tap()
        let confirm = app.buttons["決定する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: UITestID.timeout), file: file, line: line)
        confirm.tap()
        XCTAssertTrue(app.otherElements[UITestID.resultScreen].waitForNonExistence(timeout: UITestID.timeout), file: file, line: line)
        XCTAssertTrue(app.otherElements[UITestID.home].waitForExistence(timeout: UITestID.timeout), file: file, line: line)
    }

    /// S-07 の候補のカードのうち、`text`（場所名など）を含むもの
    @MainActor
    private func candidateCard(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", UITestID.candidateCardPrefix))
            .containing(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }
}
