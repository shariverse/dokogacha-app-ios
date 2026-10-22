//
//  SettingsModelDeleteAccountTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 設定の「アカウントを削除」（02 の §2.6 F-06）の確認・削除・端末の値の消去・サインアウト・二重送信の防止・失敗のトーストを、
/// 擬似のサーバーで確かめる
struct SettingsModelDeleteAccountTests {
    typealias ControlledAuth = OnboardingModelTests.ControlledAuth

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

        model.deleteAccountTapped()
        #expect(model.isConfirmingDeletion)
        // 確認を出しただけでは削除しない
        #expect(auth.deleteCount == 0)

        model.isConfirmingDeletion = false
        model.deletionConfirmed()
        #expect(await AsyncTestSupport.eventually { auth.signOutCount == 1 })
        #expect(auth.deleteCount == 1)
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

        await model.deleteAccount()
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

        model.deletionConfirmed()
        #expect(await AsyncTestSupport.eventually { auth.isWaitingForDelete })
        #expect(model.activeAction == .deleteAccount)
        #expect(!model.canStartAction)
        model.deletionConfirmed()
        model.deleteAccountTapped()
        #expect(!model.isConfirmingDeletion)

        auth.finishDelete()
        #expect(await AsyncTestSupport.eventually { auth.signOutCount == 1 })
        #expect(auth.deleteCount == 1)
    }
}
