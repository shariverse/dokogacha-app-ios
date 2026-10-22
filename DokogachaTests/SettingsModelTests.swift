//
//  SettingsModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の表示名の変更（02 の F-01「表示名は設定画面から変更できる」）の表示・検証・保存・二重送信の防止・通信エラーを確かめる
struct SettingsModelTests {
    typealias ControlledAuth = OnboardingModelTests.ControlledAuth

    /// 購読が失敗で終わったら、待たずにやり直す
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }
    /// 購読が失敗で終わったら、やり直さずに終える
    static let stopResubscribe = ResubscribeDelay(delay: .zero) { _ in throw CancellationError() }

    /// 表示名を登録済み（デモの「たくみ」）の擬似の認証
    static func makeAuth(behavior: SaveBehavior = .save) -> ControlledAuth {
        ControlledAuth(behavior: behavior, scenario: .oneRoom)
    }

    static func makeModel(
        _ auth: ControlledAuth,
        toasts: DGToastCenter = OnboardingModelTests.makeToasts(),
        userID: String = DemoScenario.myUserID,
        resubscribeDelay: ResubscribeDelay = immediateResubscribe
    ) -> SettingsModel {
        SettingsModel(userID: userID, auth: auth, toasts: toasts, resubscribeDelay: resubscribeDelay)
    }

    /// プロフィールを購読し、届いた今の表示名を出せる状態にして返す（購読の Task も返す。テストの終わりに cancel する）
    static func observedModel(
        _ auth: ControlledAuth,
        toasts: DGToastCenter = OnboardingModelTests.makeToasts()
    ) async throws -> (SettingsModel, Task<Void, Never>) {
        let model = makeModel(auth, toasts: toasts)
        let observing = Task { await model.observe() }
        try #require(await AsyncTestSupport.eventually { model.displayName != nil })
        return (model, observing)
    }

    // MARK: 表示

    /// 購読が届くまでは読み込み中で、行を押せない。届いたら今の表示名を出す
    @Test
    func showsCurrentDisplayName() async throws {
        let auth = Self.makeAuth()
        let model = Self.makeModel(auth)
        #expect(!model.hasLoadedProfile)
        #expect(model.displayName == nil)
        #expect(!model.canEditName)

        let observing = Task { await model.observe() }
        #expect(await AsyncTestSupport.eventually { model.hasLoadedProfile })
        #expect(model.displayName == "たくみ")
        #expect(model.canEditName)

        // ほかの端末で名前が変わっても、購読で新しい名前になる
        _ = try auth.server.saveProfile(SaveProfileRequest(displayName: "たくみ2"), by: DemoScenario.myUserID)
        #expect(await AsyncTestSupport.eventually { model.displayName == "たくみ2" })
        observing.cancel()
    }

    /// 購読が失敗したらトーストを 1 回だけ出し、画面は読み込み中のまま壊さない
    @Test
    func subscriptionFailureShowsToastOnce() async {
        let auth = Self.makeAuth()
        let toasts = OnboardingModelTests.makeToasts()
        // 自分のでない uid を購読する（ルールで拒まれる）
        let model = Self.makeModel(auth, toasts: toasts, userID: "someone-else", resubscribeDelay: Self.stopResubscribe)
        await model.observe()
        #expect(toasts.current?.text == InMemoryServer.permissionDenied.message)
        #expect(!model.hasLoadedProfile)
        #expect(!model.canEditName)
    }

    // MARK: 編集と検証

    /// 行を押すと、今の名前を入れた編集のシートを出す。同じ名前のままでは保存できない
    @Test
    func beginEditingFillsCurrentName() async throws {
        let (model, observing) = try await Self.observedModel(Self.makeAuth())
        model.beginEditingName()
        #expect(model.isEditingName)
        #expect(model.draftName == "たくみ")
        #expect(!model.canSave)

        // 前後に空白を足しただけでも、同じ名前なので保存できない
        model.draftName = " たくみ "
        #expect(!model.canSave)
        model.draftName = "ゆい"
        #expect(model.canSave)
        observing.cancel()
    }

    /// 名前が届く前は、行を押してもシートを出さない
    @Test
    func beginEditingBeforeLoadDoesNothing() {
        let model = Self.makeModel(Self.makeAuth())
        model.beginEditingName()
        #expect(!model.isEditingName)
    }

    /// 1〜10 文字の規則（S-01 と同じ）で、空・11 文字・使えない文字は保存できない
    @Test(arguments: [
        ("", nil),
        ("   ", nil),
        ("12345678901", NameInputCheck.Issue.tooLong(limit: 10)),
        ("ゆ\nい", NameInputCheck.Issue.forbiddenCharacter)
    ] as [(String, NameInputCheck.Issue?)])
    func invalidNamesCannotBeSaved(input: String, issue: NameInputCheck.Issue?) async throws {
        let (model, observing) = try await Self.observedModel(Self.makeAuth())
        model.beginEditingName()
        model.draftName = input
        #expect(model.draftCheck.issue == issue)
        #expect(!model.canSave)
        observing.cancel()
    }

    // MARK: 保存

    /// 保存すると、前後の空白を取り除いた名前でプロフィールと参加中のルームのメンバーが変わり、シートを閉じる
    @Test
    func saveUpdatesProfileAndClosesSheet() async throws {
        let auth = Self.makeAuth()
        let toasts = OnboardingModelTests.makeToasts()
        let (model, observing) = try await Self.observedModel(auth, toasts: toasts)
        model.beginEditingName()
        model.draftName = "  ゆい "
        await model.save()

        #expect(auth.savedNames == ["ゆい"])
        #expect(auth.server.users[DemoScenario.myUserID]?.displayName == "ゆい")
        #expect(auth.server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID]?.displayName == "ゆい")
        #expect(model.displayName == "ゆい")
        #expect(!model.isEditingName)
        #expect(!model.isSaving)
        #expect(toasts.current == nil)
        observing.cancel()
    }

    /// 送っている途中は、もう一度押しても送らない（二重送信の防止）。Task が動き出す前に続けて押しても 1 回だけ
    @Test
    func preventsDoubleSave() async throws {
        let auth = Self.makeAuth(behavior: .suspend)
        let (model, observing) = try await Self.observedModel(auth)
        model.beginEditingName()
        model.draftName = "ゆい"

        // 間に await を挟まずに 2 回押す
        model.saveTapped()
        model.saveTapped()
        #expect(await AsyncTestSupport.eventually { auth.isWaiting })
        #expect(model.isSaving)
        #expect(!model.canSave)

        model.saveTapped()
        await model.save()
        #expect(auth.savedNames == ["ゆい"])

        auth.finishSave()
        #expect(await AsyncTestSupport.eventually { !model.isEditingName })
        #expect(!model.isSaving)
        #expect(auth.savedNames == ["ゆい"])
        observing.cancel()
    }

    /// 通信エラーではトースト（AppError の文言）を出し、シートと入力を残してもう一度保存できる
    @Test
    func networkFailureShowsToastAndKeepsSheet() async throws {
        let auth = Self.makeAuth(behavior: .fail(ServerFailure(code: .unavailable)))
        let toasts = OnboardingModelTests.makeToasts()
        let (model, observing) = try await Self.observedModel(auth, toasts: toasts)
        model.beginEditingName()
        model.draftName = "ゆい"
        await model.save()

        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.isEditingName)
        #expect(model.draftName == "ゆい")
        #expect(model.displayName == "たくみ")
        #expect(model.canSave)

        auth.behavior = .save
        await model.save()
        #expect(!model.isEditingName)
        #expect(model.displayName == "ゆい")
        observing.cancel()
    }

    /// シートを閉じて送っている途中の保存を止めたら、トーストを出さない
    @Test
    func cancelSaveShowsNoToast() async throws {
        let auth = Self.makeAuth(behavior: .fail(CancellationError()))
        let toasts = OnboardingModelTests.makeToasts()
        let (model, observing) = try await Self.observedModel(auth, toasts: toasts)
        model.beginEditingName()
        model.draftName = "ゆい"

        model.saveTapped()
        model.cancelSave()
        #expect(await AsyncTestSupport.eventually { !model.isSaving && model.canSave })
        #expect(toasts.current == nil)
        #expect(model.displayName == "たくみ")
        observing.cancel()
    }
}
