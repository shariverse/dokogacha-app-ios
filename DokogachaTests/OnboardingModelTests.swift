//
//  OnboardingModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// `OnboardingModelTests.ControlledAuth` の登録のふるまい
enum SaveBehavior {
    /// 擬似のサーバーに保存する
    case save
    /// このエラーを投げる
    case fail(any Error)
    /// `finishSave()` を呼ぶまで止まり、その後で保存する
    case suspend
}

/// S-01 オンボーディング（F-01「表示名 1〜10 文字、必須」）の入力の検証・登録・二重送信の防止・通信エラーを確かめる
struct OnboardingModelTests {
    /// 表示名の登録の結果を決められ、送られた名前を記録する擬似の認証（擬似のサーバーの上に作る）
    final class ControlledAuth: AuthService {
        let server = InMemoryServer.demo(.firstLaunch)
        var behavior: SaveBehavior
        /// 送られた表示名（送られた順）
        private(set) var savedNames: [String] = []
        private var pending: CheckedContinuation<Void, Never>?

        init(behavior: SaveBehavior = .save) {
            self.behavior = behavior
        }

        /// 登録の途中で止まっているか
        var isWaiting: Bool {
            pending != nil
        }

        /// 止めていた登録を進める
        func finishSave() {
            pending?.resume()
            pending = nil
        }

        var currentUserID: String? {
            server.currentUserID
        }

        func userIDChanges() -> AsyncStream<String?> {
            server.userIDChanges()
        }

        func signInAnonymously() async throws -> String {
            try await server.signInAnonymously()
        }

        func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
            server.profile(userID: userID)
        }

        func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
            savedNames.append(displayName)
            switch behavior {
            case .save:
                break
            case let .fail(error):
                throw error
            case .suspend:
                await withCheckedContinuation { pending = $0 }
            }
            return try await server.saveDisplayName(displayName)
        }

        func linkWithApple(_ credential: AppleIDCredential) async throws {}
    }

    /// トーストを出したままにする窓口（テストの間に 2.2 秒が過ぎて消えないよう、出しておく時間を長くする）
    static func makeToasts() -> DGToastCenter {
        DGToastCenter(visibleFor: .seconds(3_600))
    }

    /// 1〜10 文字に収まる入力（前後の空白は数えない）
    nonisolated static let acceptedNames: [(input: String, count: Int)] = [
        ("ゆ", 1),
        ("ゆい", 2),
        ("1234567890", 10),
        ("  ゆい  ", 2),
        ("👨‍👩‍👧‍👦", 1)
    ]

    /// 空（必須）のときは押せず、エラーの文言も出さない
    @Test(arguments: ["", "   ", "\u{200B}"])
    func emptyInputCannotSubmit(input: String) {
        let model = OnboardingModel(auth: ControlledAuth(), toasts: Self.makeToasts())
        model.displayName = input
        #expect(model.characterCount == 0)
        #expect(model.validatedName == nil)
        #expect(model.inputIssue == nil)
        #expect(!model.canSubmit)
    }

    /// 1〜10 文字なら押せる
    @Test(arguments: Self.acceptedNames)
    func acceptsOneToTenCharacters(name: (input: String, count: Int)) {
        let model = OnboardingModel(auth: ControlledAuth(), toasts: Self.makeToasts())
        model.displayName = name.input
        #expect(model.characterCount == name.count)
        #expect(model.characterLimit == 10)
        #expect(model.inputIssue == nil)
        #expect(model.canSubmit)
    }

    /// 11 文字は押せず、上限を超えたことを出す
    @Test
    func rejectsElevenCharacters() {
        let model = OnboardingModel(auth: ControlledAuth(), toasts: Self.makeToasts())
        model.displayName = "12345678901"
        #expect(model.characterCount == 11)
        #expect(model.inputIssue == .tooLong(limit: 10))
        #expect(!model.canSubmit)
    }

    /// 改行などの使えない文字は押せず、その理由を出す（backend の `saveProfile` と同じ規則）
    @Test
    func rejectsForbiddenCharacter() {
        let model = OnboardingModel(auth: ControlledAuth(), toasts: Self.makeToasts())
        model.displayName = "ゆ\nい"
        #expect(model.inputIssue == .forbiddenCharacter)
        #expect(!model.canSubmit)
    }

    /// 登録すると、前後の空白を取り除いた名前でプロフィールができ、もう押せなくなる
    @Test
    func submitSavesTrimmedName() async throws {
        let auth = ControlledAuth()
        let toasts = Self.makeToasts()
        let model = OnboardingModel(auth: auth, toasts: toasts)
        model.displayName = "  ゆい "
        await model.submit()

        #expect(auth.savedNames == ["ゆい"])
        let profile = try #require(auth.server.users[DemoScenario.myUserID])
        #expect(profile.displayName == "ゆい")
        #expect(model.didRegister)
        #expect(!model.isSubmitting)
        #expect(!model.canSubmit)
        #expect(toasts.current == nil)
    }

    /// 送っている途中は、もう一度押しても送らない（二重送信の防止）
    @Test
    func preventsDoubleSubmit() async {
        let auth = ControlledAuth(behavior: .suspend)
        let model = OnboardingModel(auth: auth, toasts: Self.makeToasts())
        model.displayName = "ゆい"

        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { auth.isWaiting })
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)

        // 送っている途中に、ボタン・キーボードの完了・直接の呼び出しで何度押しても送らない
        model.submitTapped()
        model.submitTapped()
        await model.submit()
        #expect(auth.savedNames == ["ゆい"])

        auth.finishSave()
        #expect(await AsyncTestSupport.eventually { model.didRegister })
        #expect(!model.isSubmitting)
        #expect(auth.savedNames == ["ゆい"])
    }

    /// 通信エラーではトースト（AppError の文言）を出し、入力を残してもう一度押せる
    @Test
    func networkFailureShowsToastAndAllowsRetry() async {
        let auth = ControlledAuth(behavior: .fail(ServerFailure(code: .unavailable)))
        let toasts = Self.makeToasts()
        let model = OnboardingModel(auth: auth, toasts: toasts)
        model.displayName = "ゆい"
        await model.submit()

        #expect(toasts.current?.text == AppError(.network).message)
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(!model.isSubmitting)
        #expect(!model.didRegister)
        #expect(model.displayName == "ゆい")
        #expect(model.canSubmit)

        // 電波が戻ったら、同じ入力でもう一度送れる
        auth.behavior = .save
        await model.submit()
        #expect(model.didRegister)
        #expect(auth.savedNames == ["ゆい", "ゆい"])
    }

    /// サーバーが入力を拒んだら、その理由の文言を出す
    @Test
    func serverRejectionShowsReasonMessage() async {
        let failure = ServerFailure(code: .invalidArgument, reason: AppError.Reason.invalidArgument.rawValue)
        let auth = ControlledAuth(behavior: .fail(failure))
        let toasts = Self.makeToasts()
        let model = OnboardingModel(auth: auth, toasts: toasts)
        model.displayName = "ゆい"
        await model.submit()
        #expect(toasts.current?.text == "入力内容を確認してください")
    }

    /// cancel（画面を閉じた）のときはトーストを出さない
    @Test
    func cancellationShowsNoToast() async {
        let auth = ControlledAuth(behavior: .fail(CancellationError()))
        let toasts = Self.makeToasts()
        let model = OnboardingModel(auth: auth, toasts: toasts)
        model.displayName = "ゆい"
        await model.submit()
        #expect(toasts.current == nil)
        #expect(model.canSubmit)
    }
}
