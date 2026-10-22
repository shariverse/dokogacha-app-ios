//
//  SettingsModelAppleLinkTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の Sign in with Apple の連携（02 の §1 F-01「設定画面から Sign in with Apple に連携できる」）を、
/// Apple の認証を差し替えて擬似のサーバーで確かめる（nonce・連携済み・やめたとき・別のアカウントで使われていたとき・失敗）
struct SettingsModelAppleLinkTests {
    typealias ControlledAuth = OnboardingModelTests.ControlledAuth

    /// Apple の認証を差し替えたもの（渡された nonce のハッシュを記録し、決めた ID トークンを返す。nil ならやめた）
    final class StubAuthorizer: AppleAuthorizing {
        var idToken: String?
        var error: AppError?
        private(set) var nonceHashes: [String] = []

        init(idToken: String? = "apple-account-1") {
            self.idToken = idToken
        }

        func authorize(nonceHash: String) async throws -> String? {
            nonceHashes.append(nonceHash)
            if let error {
                throw error
            }
            return idToken
        }
    }

    /// 決まった nonce
    static let nonce = "fixed-nonce-for-test"

    static func makeModel(
        _ auth: ControlledAuth,
        toasts: DGToastCenter = OnboardingModelTests.makeToasts()
    ) -> SettingsModel {
        SettingsModel(
            userID: auth.currentUserID ?? DemoScenario.myUserID,
            auth: auth,
            purchases: .disabled,
            toasts: toasts,
            resubscribeDelay: SettingsModelTests.stopResubscribe,
            makeNonce: { Self.nonce }
        )
    }

    /// 連携すると「連携済み」になり、Apple には nonce の SHA-256 を、連携には元の nonce と ID トークンを渡す
    @Test
    func linkMarksLinkedAndUsesNonce() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)
        let authorizer = StubAuthorizer()
        #expect(!model.isLinkedWithApple)

        await model.linkApple(using: authorizer)
        #expect(model.isLinkedWithApple)
        #expect(auth.isLinkedWithApple)
        #expect(authorizer.nonceHashes == [AppleSignInNonce.sha256(Self.nonce)])
        #expect(auth.linkedCredentials == [AppleIDCredential(idToken: "apple-account-1", rawNonce: Self.nonce)])
        #expect(toasts.current?.text == "Apple でサインインを連携しました")
        #expect(model.activeAction == nil)

        // 連携済みなら、もう Apple の認証を出さない
        await model.linkApple(using: authorizer)
        #expect(authorizer.nonceHashes.count == 1)
    }

    /// 連携済みのアカウントで開いたら、最初から「連携済み」
    @Test
    func alreadyLinkedAccountShowsLinked() {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = DemoScenario.myUserID
        #expect(Self.makeModel(auth).isLinkedWithApple)
    }

    /// Apple の認証の画面でやめたら、連携もトーストもしない
    @Test
    func cancelledAuthorizationDoesNothing() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)

        await model.linkApple(using: StubAuthorizer(idToken: nil))
        #expect(!model.isLinkedWithApple)
        #expect(auth.linkedCredentials.isEmpty)
        #expect(toasts.current == nil)
    }

    /// Apple の認証・連携に失敗したらトーストを出し、未連携のまま（もう一度押せる）
    @Test
    func failureShowsToast() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)
        let authorizer = StubAuthorizer()
        authorizer.error = AppError(.appleSignInFailed)

        await model.linkApple(using: authorizer)
        #expect(toasts.current?.text == "Apple でサインインできませんでした")
        #expect(!model.isLinkedWithApple)
        #expect(model.canStartAction)

        let network = ControlledAuth(scenario: .oneRoom)
        network.linkError = AppError(.network)
        let networkToasts = OnboardingModelTests.makeToasts()
        await Self.makeModel(network, toasts: networkToasts).linkApple(using: StubAuthorizer())
        #expect(networkToasts.current?.text == "通信できませんでした")
    }

    /// その Apple ID が別のアカウントで使われていたら、連携せずに確認を出す。「サインインし直す」でそのアカウントに替わる
    /// （02 の F-01 の AC「別端末で同じ Apple ID でサインインしたときに参加ルームが復元される」）
    @Test
    func appleIDInUseOffersSwitchingAccount() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        // 前の端末のアカウント（別の uid）が、この Apple ID に連携済み
        auth.server.appleAccounts["apple-account-1"] = "previous-device-user"
        let model = Self.makeModel(auth)

        await model.linkApple(using: StubAuthorizer())
        #expect(model.isConfirmingAccountSwitch)
        #expect(!model.isLinkedWithApple)
        #expect(auth.currentUserID == DemoScenario.myUserID)

        await model.switchToLinkedAppleAccount()
        #expect(auth.currentUserID == "previous-device-user")
        #expect(auth.isLinkedWithApple)
    }

    /// 確認でやめたら（サインインし直さない）、今のアカウントのまま。確認を経ずにサインインし直そうとしても失敗する
    @Test
    func switchingWithoutPendingAccountFails() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)

        await model.switchToLinkedAppleAccount()
        #expect(auth.currentUserID == DemoScenario.myUserID)
        #expect(toasts.current?.text == "Apple でサインインできませんでした")
    }

    /// 擬似のサーバーでは、1 つのユーザーに Apple のアカウントは 1 つまで（別の Apple ID を連携しようとしても付け替えない）
    @Test
    func inMemoryServerKeepsOneAppleAccountPerUser() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        #expect(try await server.linkWithApple(AppleIDCredential(idToken: "first", rawNonce: "n")) == .linked)
        #expect(try await server.linkWithApple(AppleIDCredential(idToken: "second", rawNonce: "n")) == .linked)
        #expect(server.appleAccounts == ["first": DemoScenario.myUserID])

        server.simulateSignOut()
        #expect(!server.isLinkedWithApple)
        await #expect(throws: AppError(.unauthenticated)) {
            try await server.linkWithApple(AppleIDCredential(idToken: "first", rawNonce: "n"))
        }
    }
}
