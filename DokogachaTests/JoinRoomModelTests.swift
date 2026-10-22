//
//  JoinRoomModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-05 招待コードで参加・S-06 参加確認（F-04）の入力の正規化・確認・参加・エラーの出し分け・二重送信の防止を確かめる
struct JoinRoomModelTests {
    /// テストで使う窓口
    struct Fixture {
        let functions: JoinControlledFunctions
        let toasts: DGToastCenter

        /// S-05 の画面の状態
        func codeModel() -> JoinByCodeModel {
            JoinByCodeModel(functions: functions, toasts: toasts)
        }

        /// S-06 の画面の状態（`code` を確かめた結果から作る）
        func confirmModel(code: String = DemoScenario.joinableInviteCode) async throws -> JoinConfirmModel {
            let inviteCode = try #require(InviteCode(code))
            let preview = try await functions.server.previewRoom(PreviewRoomRequest(inviteCode: code))
            return JoinConfirmModel(
                destination: JoinConfirmDestination(preview: preview, inviteCode: inviteCode),
                functions: functions,
                toasts: toasts
            )
        }
    }

    /// デモの `joinable`（自分のルームは無く、参加できる・満員・決定後のルームがある）の擬似のサーバーと窓口を作る
    static func make(_ scenario: DemoScenario = .joinable) -> Fixture {
        let functions = JoinControlledFunctions(server: InMemoryServer.demo(scenario))
        // トーストを出したままにする（テストの間に 2.2 秒が過ぎて消えないよう、出しておく時間を長くする）
        return Fixture(functions: functions, toasts: DGToastCenter(visibleFor: .seconds(3_600)))
    }

    // MARK: デモのデータ

    /// `joinable` の招待コードはどれも正しい形で、自分はどのルームのメンバーでもない
    @Test
    func joinableScenarioHasRoomsToJoin() throws {
        let server = InMemoryServer.demo(.joinable)
        for code in [DemoScenario.joinableInviteCode, DemoScenario.fullInviteCode, DemoScenario.decidedInviteCode] {
            #expect(InviteCode(code) != nil)
            let roomID = try #require(server.inviteCodes[code]?.roomId)
            #expect(server.rooms[roomID]?.members[DemoScenario.myUserID] == nil)
        }
        #expect(server.users[DemoScenario.myUserID] != nil)
        let full = try #require(server.inviteCodes[DemoScenario.fullInviteCode].flatMap { server.rooms[$0.roomId] })
        #expect(full.room.memberCount == DomainConstants.Limits.maxMembers)
        #expect(full.members.count == DomainConstants.Limits.maxMembers)
    }

    // MARK: S-05 入力の正規化

    /// 打った・貼り付けた文字を英大文字・`ABC-123` の形にし、6 文字で切る（03 の S-05）
    @Test(arguments: [
        ("qw5", "QW5"),
        ("qw58rt", "QW5-8RT"),
        ("QW5-8RT", "QW5-8RT"),
        (" qw5 8rt ", "QW5-8RT"),
        ("ｑｗ５ー８ｒｔ", "QW5-8RT"),
        ("QW58RTXYZ", "QW5-8RT")
    ])
    func normalizesInput(value: (input: String, expected: String)) {
        let model = Self.make().codeModel()
        model.codeText = value.input
        #expect(model.codeText == value.expected)
    }

    /// 6 文字に満たないと押せず、6 文字なら押せる（使えない文字を含んでも押せる）
    @Test
    func canSubmitOnlyWithSixCharacters() {
        let model = Self.make().codeModel()
        #expect(!model.canSubmit)
        model.codeText = "QW58R"
        #expect(model.enteredCount == 5)
        #expect(!model.canSubmit)
        model.codeText = "QW58RT"
        #expect(model.code?.value == "QW58RT")
        #expect(model.canSubmit)
        model.codeText = "QW58R0"
        #expect(model.code == nil)
        #expect(model.canSubmit)
    }

    // MARK: S-05 確認

    /// 正しいコードで確かめると、S-06 にルームの値（ルーム名・作成者名・メンバー数・候補数・状態）を渡す
    @Test
    func submitOpensConfirmWithPreview() async throws {
        let fixture = Self.make()
        let model = fixture.codeModel()
        model.codeText = "qw5-8rt"
        await model.submit()

        #expect(fixture.functions.previewRequests == [PreviewRoomRequest(inviteCode: "QW58RT")])
        guard case let .confirm(destination) = model.outcome else {
            Issue.record("S-06 に進んでいない: \(String(describing: model.outcome))")
            return
        }
        #expect(destination.inviteCode.value == "QW58RT")
        #expect(destination.preview == RoomPreview(
            roomId: DemoScenario.joinableRoomID,
            name: "夏の花火大会",
            ownerName: "はるか",
            memberCount: 3,
            candidateCount: 2,
            status: .open,
            alreadyMember: false
        ))
        #expect(model.errorMessage == nil)
        #expect(fixture.toasts.current == nil)

        // S-06 に進んだら行き先を消し、戻ってからもう一度確かめられる
        model.clearOutcome()
        #expect(model.outcome == nil)
        #expect(model.canSubmit)
    }

    /// すでにメンバーなら、S-06 を出さずにルームを開く（03 の S-06）
    @Test
    func alreadyMemberOpensRoomDirectly() async throws {
        let fixture = Self.make(.oneRoom)
        let model = fixture.codeModel()
        model.codeText = DemoScenario.inviteCode
        await model.submit()
        #expect(model.outcome == .openRoom(roomID: DemoScenario.roomID))
    }

    /// F-04 の AC のエラーは入力欄の下に 02 の文言で出し（トーストは出さない）、入力を直すと消える
    @Test(arguments: [
        ("ZZZZZZ", "招待コードが見つかりません"),
        (DemoScenario.fullInviteCode, "このルームは満員です（最大20人）"),
        (DemoScenario.decidedInviteCode, "このルームはもう行き先が決まっています")
    ])
    func joinErrorsShowUnderField(value: (code: String, message: String)) async {
        let fixture = Self.make()
        let model = fixture.codeModel()
        model.codeText = value.code
        await model.submit()

        #expect(model.errorMessage == value.message)
        #expect(model.outcome == nil)
        #expect(fixture.toasts.current == nil)
        #expect(model.canSubmit)

        // 同じ文字のままでは消さず、直すと消す
        let same = model.codeText
        model.codeText = same
        #expect(model.errorMessage == value.message)
        model.codeText = "ZZZZZ"
        #expect(model.errorMessage == nil)
    }

    /// 使えない文字（`0 O 1 I`）を含む 6 文字は、サーバーに送らずに「招待コードが見つかりません」を出す
    @Test
    func invalidCharactersShowNotFoundWithoutCalling() async {
        let fixture = Self.make()
        let model = fixture.codeModel()
        model.codeText = "QW58R0"
        await model.submit()
        #expect(model.errorMessage == "招待コードが見つかりません")
        #expect(fixture.functions.previewRequests.isEmpty)
    }

    /// 通信エラーはトースト「通信できませんでした」で出し（入力欄の下には出さない）、もう一度押せる
    @Test
    func networkFailureShowsToastAndAllowsRetry() async {
        let fixture = Self.make()
        fixture.functions.previewBehavior = .fail(ServerFailure(code: .unavailable))
        let model = fixture.codeModel()
        model.codeText = DemoScenario.joinableInviteCode
        await model.submit()

        #expect(fixture.toasts.current?.text == "通信できませんでした")
        #expect(model.errorMessage == nil)
        #expect(model.outcome == nil)
        #expect(model.canSubmit)

        fixture.functions.previewBehavior = .pass
        await model.submit()
        #expect(model.outcome != nil)
        #expect(fixture.functions.previewRequests.count == 2)
    }

    /// 確かめている途中は、もう一度押しても送らず、入力も変えられない（二重送信の防止）
    @Test
    func preventsDoubleSubmit() async {
        let fixture = Self.make()
        fixture.functions.previewBehavior = .suspend
        let model = fixture.codeModel()
        model.codeText = DemoScenario.joinableInviteCode

        model.submitTapped()
        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        #expect(!model.isEditable)
        model.submitTapped()
        await model.submit()
        #expect(fixture.functions.previewRequests.count == 1)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.outcome != nil })
        #expect(fixture.functions.previewRequests.count == 1)
    }

    /// 画面が消えたら確かめている途中の確認を止め、結果が返っても進まず、トーストも出さない
    @Test
    func cancelSubmitStopsWithoutOutcomeOrToast() async {
        let fixture = Self.make()
        fixture.functions.previewBehavior = .suspend
        let model = fixture.codeModel()
        model.codeText = DemoScenario.joinableInviteCode

        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        model.cancelSubmit()
        fixture.functions.finish()

        #expect(await AsyncTestSupport.eventually { !model.isSubmitting })
        #expect(model.outcome == nil)
        #expect(fixture.toasts.current == nil)
    }

    // MARK: S-06 参加

    /// 「参加する」で参加し、ルームの ID を渡す（F-04 の AC「正しいコードで参加でき、ルーム画面が開く」）
    @Test
    func joinAddsMeAndOpensRoom() async throws {
        let fixture = Self.make()
        let model = try await fixture.confirmModel()
        await model.join()

        #expect(fixture.functions.joinRequests == [JoinRoomRequest(inviteCode: DemoScenario.joinableInviteCode)])
        #expect(model.joinedRoomID == DemoScenario.joinableRoomID)
        let record = try #require(fixture.functions.server.rooms[DemoScenario.joinableRoomID])
        #expect(record.members[DemoScenario.myUserID]?.ready == false)
        #expect(record.room.memberCount == 4)
        #expect(!model.canJoin)
        #expect(fixture.toasts.current == nil)
    }

    /// 確かめてから押すまでに満員になったら、トーストで 02 の文言を出し、ルームに進まない
    @Test
    func joinFailureShowsToast() async throws {
        let fixture = Self.make()
        let model = try await fixture.confirmModel()
        fixture.functions.server.rooms[DemoScenario.joinableRoomID]?.room.memberCount = DomainConstants.Limits.maxMembers
        await model.join()

        #expect(fixture.toasts.current?.text == "このルームは満員です（最大20人）")
        #expect(model.joinedRoomID == nil)
        #expect(model.canJoin)
    }

    /// 送っている途中は、もう一度押しても送らない（二重送信の防止）
    @Test
    func preventsDoubleJoin() async throws {
        let fixture = Self.make()
        let model = try await fixture.confirmModel()
        fixture.functions.joinBehavior = .suspend

        model.joinTapped()
        model.joinTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        #expect(model.isJoining)
        #expect(!model.canJoin)
        await model.join()
        #expect(fixture.functions.joinRequests.count == 1)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.joinedRoomID != nil })
        #expect(fixture.functions.joinRequests.count == 1)
    }

    /// 画面が消えたら送っている途中の参加を止め、結果が返ってもルームへ進まず、トーストも出さない
    @Test
    func cancelJoinStopsWithoutNavigatingOrToast() async throws {
        let fixture = Self.make()
        let model = try await fixture.confirmModel()
        fixture.functions.joinBehavior = .suspend

        model.joinTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        model.cancelJoin()
        fixture.functions.finish()

        #expect(await AsyncTestSupport.eventually { !model.isJoining })
        #expect(model.joinedRoomID == nil)
        #expect(fixture.toasts.current == nil)
    }

    /// cancel（画面を閉じた）のエラーではトーストを出さない
    @Test
    func cancellationShowsNoToast() async throws {
        let fixture = Self.make()
        fixture.functions.previewBehavior = .fail(CancellationError())
        fixture.functions.joinBehavior = .fail(CancellationError())
        let codeModel = fixture.codeModel()
        codeModel.codeText = DemoScenario.joinableInviteCode
        await codeModel.submit()
        let confirmModel = try await fixture.confirmModel()
        await confirmModel.join()

        #expect(fixture.toasts.current == nil)
        #expect(codeModel.errorMessage == nil)
        #expect(confirmModel.canJoin)
    }
}
