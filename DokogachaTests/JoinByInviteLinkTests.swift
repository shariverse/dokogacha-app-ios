//
//  JoinByInviteLinkTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 招待リンクで開いた S-05（`JoinByCodeModel` に招待コードを渡して始める）が、すぐに確かめて S-06 に進むことを確かめる（タスク 34）
struct JoinByInviteLinkTests {
    /// デモの `joinable` の擬似のサーバーと窓口
    static func make(_ scenario: DemoScenario = .joinable) -> (functions: JoinControlledFunctions, toasts: DGToastCenter) {
        (JoinControlledFunctions(server: InMemoryServer.demo(scenario)), DGToastCenter(visibleFor: .seconds(3_600)))
    }

    /// 入力欄に招待コードを表示の形で入れた状態で始め、最初の 1 回だけ自動で確かめて S-06 に進む
    @Test
    func submitsInitialCodeOnceAndOpensConfirm() async throws {
        let (functions, toasts) = Self.make()
        let code = try #require(InviteCode(DemoScenario.joinableInviteCode))
        let model = JoinByCodeModel(functions: functions, toasts: toasts, initialCode: code)
        #expect(model.codeText == "QW5-8RT")
        #expect(model.canSubmit)

        model.submitInitialCodeIfNeeded()
        #expect(await AsyncTestSupport.eventually { model.outcome != nil })
        guard case let .confirm(destination) = model.outcome else {
            Issue.record("S-06 に進んでいない: \(String(describing: model.outcome))")
            return
        }
        #expect(destination.inviteCode == code)
        #expect(destination.preview.name == "夏の花火大会")
        #expect(functions.previewRequests == [PreviewRoomRequest(inviteCode: "QW58RT")])

        // S-06 から戻って S-05 がもう一度出ても、確かめ直さない
        model.clearOutcome()
        model.submitInitialCodeIfNeeded()
        #expect(await AsyncTestSupport.eventually { !model.isSubmitting })
        #expect(functions.previewRequests.count == 1)
        #expect(model.outcome == nil)
    }

    /// コードを渡さずに始めたとき（ホームの「招待コードで参加」）は、自動で確かめない
    @Test
    func doesNotSubmitWithoutInitialCode() async {
        let (functions, toasts) = Self.make()
        let model = JoinByCodeModel(functions: functions, toasts: toasts)
        #expect(model.codeText.isEmpty)
        model.submitInitialCodeIfNeeded()
        #expect(!model.isSubmitting)
        #expect(functions.previewRequests.isEmpty)
    }

    /// すでにメンバーのルームの招待リンクなら、S-06 を出さずにルームを開く
    @Test
    func alreadyMemberOpensRoom() async throws {
        let (functions, toasts) = Self.make(.oneRoom)
        let code = try #require(InviteCode(DemoScenario.inviteCode))
        let model = JoinByCodeModel(functions: functions, toasts: toasts, initialCode: code)
        model.submitInitialCodeIfNeeded()
        #expect(await AsyncTestSupport.eventually { model.outcome != nil })
        #expect(model.outcome == .openRoom(roomID: DemoScenario.roomID))
    }

    /// 見つからない・満員のルームの招待リンクなら、S-05 の入力欄の下にエラーを出す（押したときと同じ）
    @Test(arguments: [
        ("ZZZZZZ", "招待コードが見つかりません"),
        (DemoScenario.fullInviteCode, "このルームは満員です（最大20人）")
    ])
    func showsErrorUnderField(value: (code: String, message: String)) async throws {
        let (functions, toasts) = Self.make()
        let code = try #require(InviteCode(value.code))
        let model = JoinByCodeModel(functions: functions, toasts: toasts, initialCode: code)
        model.submitInitialCodeIfNeeded()
        #expect(await AsyncTestSupport.eventually { model.errorMessage != nil })
        #expect(model.errorMessage == value.message)
        #expect(model.outcome == nil)
    }

    /// 表示名を登録する前に招待リンクで開かれる UI テスト用のシナリオは、プロフィールが無く、参加できるルームがある
    @Test
    func firstLaunchInvitedScenarioHasRoomsToJoin() {
        let server = InMemoryServer.demo(.firstLaunchInvited)
        #expect(server.users.isEmpty)
        #expect(server.inviteCodes[DemoScenario.joinableInviteCode]?.roomId == DemoScenario.joinableRoomID)
        #expect(DemoScenario.from(arguments: ["-demo-scenario", "first-launch-invited"]) == .firstLaunchInvited)
    }
}
