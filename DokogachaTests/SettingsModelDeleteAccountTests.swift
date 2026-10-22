//
//  SettingsModelDeleteAccountTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の「アカウントを削除」（02 の §2.6 F-06）の確認・削除・端末の値の消去・サインアウト・二重送信の防止・失敗のトースト、
/// Sign in with Apple に連携済みのときのトークンの取り消し（審査ガイドライン 5.1.1(v)）、失敗しても Auth のユーザーが消えていれば削除できたことにすること、
/// Sign in with Apple で別のアカウントにサインインし直す前に今のアカウントを削除すること（PR #100 の持ち越し）を、擬似のサーバーで確かめる
struct SettingsModelDeleteAccountTests {
    typealias ControlledAuth = OnboardingModelTests.ControlledAuth
    typealias StubAuthorizer = SettingsModelAppleLinkTests.StubAuthorizer

    /// 端末の値を消した回数を数える窓口
    final class DeviceDataSpy {
        private(set) var clearCount = 0

        var data: AccountDeviceData {
            AccountDeviceData { [weak self] in self?.clearCount += 1 }
        }
    }

    static func makeModel(
        _ auth: ControlledAuth,
        deviceData: AccountDeviceData = .none,
        toasts: DGToastCenter = OnboardingModelTests.makeToasts()
    ) -> SettingsModel {
        SettingsModel(
            userID: DemoScenario.myUserID,
            auth: auth,
            purchases: .disabled,
            toasts: toasts,
            deviceData: deviceData,
            resubscribeDelay: SettingsModelTests.stopResubscribe
        )
    }

    /// 「アカウントを削除」で確認を出し、「削除する」でサーバーで削除してから、端末の値を消してサインアウトする（S-01 に戻る）
    @Test
    func confirmedDeletionDeletesClearsAndSignsOut() async throws {
        let auth = ControlledAuth(scenario: .oneRoom)
        let spy = DeviceDataSpy()
        let model = Self.makeModel(auth, deviceData: spy.data)
        let authorizer = StubAuthorizer()

        model.deleteAccountTapped()
        #expect(model.isConfirmingDeletion)
        // 確認を出しただけでは削除しない
        #expect(auth.deleteCount == 0)

        model.isConfirmingDeletion = false
        model.deletionConfirmed(using: authorizer)
        #expect(await AsyncTestSupport.eventually { auth.signOutCount == 1 })
        #expect(auth.deleteCount == 1)
        // Apple に連携していないので、Apple の認証を出さず、トークンも取り消さない
        #expect(authorizer.authorizationCodeCount == 0)
        #expect(auth.accountCalls == [.delete])
        #expect(spy.clearCount == 1)
        #expect(auth.currentUserID == nil)
        // 作成者だったルームは終了し、プロフィールは消える
        #expect(auth.server.users[DemoScenario.myUserID] == nil)
        #expect(auth.server.rooms[DemoScenario.roomID]?.room.status == .closed)
        #expect(model.activeAction == nil)
    }

    /// 削除に失敗したらトーストを出し、端末の値もサインインもそのまま（もう一度押せる）
    @Test
    func failureShowsToastAndKeepsAccount() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.deleteBehavior = .fail(AppError(.network, code: .unavailable))
        let spy = DeviceDataSpy()
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, deviceData: spy.data, toasts: toasts)

        await model.deleteAccount(using: StubAuthorizer())
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(spy.clearCount == 0)
        #expect(auth.signOutCount == 0)
        #expect(auth.currentUserID == DemoScenario.myUserID)
        #expect(auth.server.users[DemoScenario.myUserID] != nil)
        #expect(model.canStartAction)
    }

    /// 送っている途中は、もう一度押しても送らない（確認も出さない）。ほかの行（購入・復元・連携）も押せない
    @Test
    func deletingTwiceSendsOnce() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.deleteBehavior = .suspend
        let model = Self.makeModel(auth)

        model.deletionConfirmed(using: StubAuthorizer())
        #expect(await AsyncTestSupport.eventually { auth.isWaitingForDelete })
        #expect(model.activeAction == .deleteAccount)
        #expect(!model.canStartAction)
        model.deletionConfirmed(using: StubAuthorizer())
        model.deleteAccountTapped()
        #expect(!model.isConfirmingDeletion)

        auth.finishDelete()
        #expect(await AsyncTestSupport.eventually { auth.signOutCount == 1 })
        #expect(auth.deleteCount == 1)
    }

    /// 別のアカウントにサインインし直すときは、先に今の匿名のアカウントを削除する
    /// （残すと参加中のルームのメンバーに残り続け、「全員OK」のルームが解禁できなくなる）
    @Test
    func switchingAccountDeletesCurrentAccountFirst() async {
        let auth = ControlledAuth(scenario: .severalRooms)
        auth.server.appleAccounts["apple-account-1"] = "previous-device-user"
        let model = Self.makeModel(auth)

        await model.linkApple(using: SettingsModelAppleLinkTests.StubAuthorizer())
        #expect(model.isConfirmingAccountSwitch)
        await model.switchToLinkedAppleAccount()

        #expect(auth.deleteCount == 1)
        #expect(auth.currentUserID == "previous-device-user")
        #expect(auth.server.users[DemoScenario.myUserID] == nil)
        // ほかの人が作ったルームからは外れる（作成者だったルームは終了する）
        #expect(auth.server.rooms[DemoScenario.othersRoomID]?.room.memberIds.contains(DemoScenario.myUserID) == false)
        #expect(auth.server.rooms[DemoScenario.roomID]?.room.status == .closed)
        // サインインし直すので、サインアウトはしない（匿名でサインインし直さない）
        #expect(auth.signOutCount == 0)
        // 今の匿名のアカウントは Apple に連携していないので、トークンを取り消さない
        #expect(auth.accountCalls == [.delete])
        #expect(auth.server.revokedAppleAuthorizationCodes.isEmpty)
    }

    /// 今のアカウントを削除できなかったら、サインインし直さない（今のアカウントのまま、もう一度押せる）
    @Test
    func switchingAccountStopsWhenDeletionFails() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = "previous-device-user"
        auth.deleteBehavior = .fail(AppError(.network, code: .unavailable))
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)

        await model.linkApple(using: SettingsModelAppleLinkTests.StubAuthorizer())
        await model.switchToLinkedAppleAccount()
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(auth.currentUserID == DemoScenario.myUserID)
        #expect(auth.server.users[DemoScenario.myUserID] != nil)
        #expect(model.canStartAction)
    }

    // MARK: Sign in with Apple のトークンの取り消し

    /// 連携済みのアカウントを削除するときは、Apple の認証をもう一度行い、受け取った authorization code でトークンを取り消してから削除する
    @Test
    func linkedAccountRevokesAppleTokenBeforeDeleting() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = DemoScenario.myUserID
        let spy = DeviceDataSpy()
        let model = Self.makeModel(auth, deviceData: spy.data)
        let authorizer = StubAuthorizer()

        await model.deleteAccount(using: authorizer)
        #expect(authorizer.authorizationCodeCount == 1)
        #expect(auth.accountCalls == [.revoke(authorizationCode: "apple-authorization-code-1"), .delete])
        #expect(auth.server.revokedAppleAuthorizationCodes == ["apple-authorization-code-1"])
        #expect(auth.server.users[DemoScenario.myUserID] == nil)
        #expect(spy.clearCount == 1)
        #expect(auth.signOutCount == 1)
    }

    /// Apple の画面でやめたら、取り消しも削除もしない（トーストも出さない。もう一度押せる）
    @Test
    func cancelingAppleAuthorizationKeepsAccount() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = DemoScenario.myUserID
        let spy = DeviceDataSpy()
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, deviceData: spy.data, toasts: toasts)
        let authorizer = StubAuthorizer()
        authorizer.code = nil

        await model.deleteAccount(using: authorizer)
        #expect(authorizer.authorizationCodeCount == 1)
        #expect(auth.accountCalls.isEmpty)
        #expect(toasts.current == nil)
        #expect(spy.clearCount == 0)
        #expect(auth.signOutCount == 0)
        #expect(auth.server.users[DemoScenario.myUserID] != nil)
        #expect(model.canStartAction)
    }

    /// トークンを取り消せなかったら削除せずにトーストを出す（Apple に連携が残ったままアカウントだけ消えるのを避ける。もう一度押せる）
    @Test(arguments: [
        (AppError(.network), "通信できませんでした"),
        (AppError(.appleRevokeFailed), "Apple でサインインの連携を解除できませんでした")
    ])
    func revokeFailureKeepsAccount(error: AppError, message: String) async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = DemoScenario.myUserID
        auth.revokeError = error
        let spy = DeviceDataSpy()
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, deviceData: spy.data, toasts: toasts)

        await model.deleteAccount(using: StubAuthorizer())
        #expect(toasts.current?.text == message)
        #expect(auth.deleteCount == 0)
        #expect(spy.clearCount == 0)
        #expect(auth.signOutCount == 0)
        #expect(auth.server.users[DemoScenario.myUserID] != nil)
        #expect(model.isLinkedWithApple)
        #expect(model.canStartAction)
    }

    /// Apple の認証の画面が失敗したら、取り消しも削除もせずにトーストを出す
    @Test
    func appleAuthorizationFailureKeepsAccount() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = DemoScenario.myUserID
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)
        let authorizer = StubAuthorizer()
        authorizer.error = AppError(.appleRevokeFailed)

        await model.deleteAccount(using: authorizer)
        #expect(toasts.current?.text == "Apple でサインインの連携を解除できませんでした")
        #expect(auth.accountCalls.isEmpty)
        #expect(auth.server.users[DemoScenario.myUserID] != nil)
    }

    // MARK: 失敗しても Auth のユーザーが消えていたとき

    /// 削除が失敗しても（応答が届かなかった）、Auth のユーザーが消えていれば削除できたことにし、端末の値を消してサインアウトする
    /// （消えた uid のまま S-01 で表示名を登録すると、`users/{uid}` を作り直してしまうため）
    @Test
    func failureAfterServerDeletedIsTreatedAsDeleted() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.deleteErrorAfterDeleting = AppError(.network, code: .unavailable)
        let spy = DeviceDataSpy()
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, deviceData: spy.data, toasts: toasts)

        await model.deleteAccount(using: StubAuthorizer())
        #expect(toasts.current == nil)
        #expect(spy.clearCount == 1)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID == nil)
    }

    /// 切り替えで、今のアカウントの削除が失敗しても消えていれば、そのままサインインし直す
    @Test
    func switchingAccountContinuesWhenDeletedDespiteFailure() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = "previous-device-user"
        auth.deleteErrorAfterDeleting = AppError(.network, code: .unavailable)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)

        await model.linkApple(using: StubAuthorizer())
        await model.switchToLinkedAppleAccount()
        #expect(toasts.current == nil)
        #expect(auth.currentUserID == "previous-device-user")
        #expect(auth.signOutCount == 0)
    }

    /// 切り替えで、今のアカウントを削除した後にサインインし直せなかったら、サインアウトしてトーストを出す
    /// （消えたアカウントのまま残らないよう、起動の流れが匿名でサインインし直して S-01 を出す）
    @Test
    func switchingAccountSignsOutWhenSignInFailsAfterDeletion() async {
        let auth = ControlledAuth(scenario: .oneRoom)
        auth.server.appleAccounts["apple-account-1"] = "previous-device-user"
        auth.signInWithLinkedError = AppError(.network)
        let toasts = OnboardingModelTests.makeToasts()
        let model = Self.makeModel(auth, toasts: toasts)

        await model.linkApple(using: StubAuthorizer())
        await model.switchToLinkedAppleAccount()
        #expect(auth.deleteCount == 1)
        #expect(auth.signOutCount == 1)
        #expect(auth.currentUserID == nil)
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.canStartAction)
    }
}
