//
//  AdCoordinatorTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 広告のまとめ役（SDK の初期化・ATT を尋ねる時機・非パーソナライズ・画面ごとの判定）を、SDK を差し替えて確かめる（02 の F-50・05 の §8）
struct AdCoordinatorTests {
    /// SDK と ATT を差し替えたもの（呼ばれたことを残す）
    private final class FakeAdService: AdService {
        var status = AdTrackingStatus.notDetermined
        /// 尋ねたときの答え
        var answer = AdTrackingStatus.denied
        var startCount = 0
        var requestCount = 0

        func start() {
            startCount += 1
        }

        func trackingStatus() -> AdTrackingStatus {
            status
        }

        func requestTrackingAuthorization() async -> AdTrackingStatus {
            requestCount += 1
            status = answer
            return answer
        }
    }

    nonisolated private static let live = AdMode.live(adUnitID: "ca-app-pub-3940256099942544/2435281174")

    @Test
    func liveModeStartsSDK() {
        let fake = FakeAdService()
        AdCoordinator(mode: Self.live, service: fake).start()
        #expect(fake.startCount == 1)
    }

    @Test(arguments: [AdMode.disabled, .placeholder])
    func testsAndScreenshotsDoNotStartSDKOrAskTracking(mode: AdMode) async {
        let fake = FakeAdService()
        let ads = AdCoordinator(mode: mode, service: fake)
        ads.start()
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(fake.startCount == 0)
        #expect(fake.requestCount == 0)
    }

    @Test
    func asksTrackingOnceAndDeniedGetsNonPersonalizedAds() async {
        let fake = FakeAdService()
        let ads = AdCoordinator(mode: Self.live, service: fake)
        #expect(ads.requestParameters == ["npa": "1"])
        await ads.requestTrackingAuthorizationIfNeeded()
        // 2 回目のルームでは尋ねない
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(fake.requestCount == 1)
        #expect(ads.trackingStatus == .denied)
        #expect(ads.requestParameters == ["npa": "1"])
    }

    @Test
    func authorizedGetsPersonalizedAds() async {
        let fake = FakeAdService()
        fake.answer = .authorized
        let ads = AdCoordinator(mode: Self.live, service: fake)
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(ads.trackingStatus == .authorized)
        #expect(ads.requestParameters.isEmpty)
    }

    @Test
    func alreadyAnsweredIsNotAskedAgain() async {
        let fake = FakeAdService()
        fake.status = .authorized
        let ads = AdCoordinator(mode: Self.live, service: fake)
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(fake.requestCount == 0)
        #expect(ads.requestParameters.isEmpty)
    }

    @Test
    func unansweredBecauseInactiveIsAskedAgainNextTime() async {
        // アプリが前面にいないと OS はダイアログを出さず notDetermined のまま返る。次にルームに入ったとき（前面に戻ったとき）に尋ね直す
        let fake = FakeAdService()
        fake.answer = .notDetermined
        let ads = AdCoordinator(mode: Self.live, service: fake)
        await ads.requestTrackingAuthorizationIfNeeded()
        fake.answer = .denied
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(fake.requestCount == 2)
        #expect(ads.trackingStatus == .denied)
    }

    @Test
    func purchaserIsNotAskedForTracking() async {
        let fake = FakeAdService()
        let ads = AdCoordinator(mode: Self.live, service: fake)
        ads.isAdFree = true
        await ads.requestTrackingAuthorizationIfNeeded()
        #expect(fake.requestCount == 0)
    }

    @Test
    func disabledModeNeverShowsAds() {
        let ads = AdCoordinator(mode: .disabled, service: FakeAdService())
        #expect(!ads.shouldShowAds(on: .home, room: nil))
    }

    @Test(arguments: [AdCoordinatorTests.live, .placeholder])
    func showsAdsByScreenAndPurchase(mode: AdMode) {
        let ads = AdCoordinator(mode: mode, service: FakeAdService())
        #expect(ads.shouldShowAds(on: .home, room: nil))
        #expect(ads.shouldShowAds(on: .room, room: RoomClosingTests.room(.open)))
        #expect(!ads.shouldShowAds(on: .gacha, room: RoomClosingTests.room(.open)))
        ads.isAdFree = true
        #expect(!ads.shouldShowAds(on: .home, room: nil))
    }
}
