//
//  AdPolicyTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// バナー広告を出すか（`AdDisplayPolicy`。05 の §8・02 の F-50〜51）、起動のしかたごとの扱い（`AdMode`）、
/// ATT を尋ねる時機と非パーソナライズ広告（`AdTrackingPolicy`）を確かめる
struct AdPolicyTests {
    /// テスト用の広告ユニット ID
    private static let adUnitID = "ca-app-pub-3940256099942544/2435281174"

    /// 購入者（`sponsor`）がいる・いないルーム
    private static func room(sponsor: AdFreeSponsor? = nil) -> Room {
        var room = RoomClosingTests.room(.open)
        room.adFreeSponsor = sponsor
        return room
    }

    // MARK: - 出す画面（F-50）

    @Test
    func onlyHomeRoomAndAddCandidateAllowAds() {
        let allowed = AdScreen.allCases.filter(\.allowsAds)
        #expect(Set(allowed) == [.home, .room, .addCandidate])
    }

    @Test(arguments: AdScreen.allCases)
    func nonPurchaserSeesAdsOnlyOnAllowedScreens(screen: AdScreen) {
        // AC「未購入ユーザーは、ホーム・ルーム・候補を追加の画面下部にバナーが出る。ガチャ・結果では出ない」
        let shows = AdDisplayPolicy.shouldShowAds(screen: screen, isAdFree: false, room: Self.room())
        #expect(shows == screen.allowsAds)
    }

    @Test
    func gachaAndResultNeverShowAds() {
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .gacha, isAdFree: false, room: Self.room()))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .result, isAdFree: false, room: Self.room()))
    }

    // MARK: - 広告非表示（F-51）

    @Test(arguments: AdScreen.allCases)
    func purchaserSeesNoAdsAnywhere(screen: AdScreen) {
        #expect(!AdDisplayPolicy.shouldShowAds(screen: screen, isAdFree: true, room: nil))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: screen, isAdFree: true, room: Self.room()))
    }

    @Test
    func sponsoredRoomHidesAdsForNonPurchasers() {
        // AC「購入者がいるルームでは、未購入のメンバーにも広告が出ない」（ルームの中の候補を追加も同じルーム）
        let sponsored = Self.room(sponsor: AdFreeSponsor(uid: "bob", displayName: "けんた"))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .room, isAdFree: false, room: sponsored))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .addCandidate, isAdFree: false, room: sponsored))
    }

    @Test
    func homeDependsOnlyOnMyPurchase() {
        // F-51「ホーム画面の広告は自分が購入者かだけで決める」。ホームにはルームを渡さない
        #expect(AdDisplayPolicy.shouldShowAds(screen: .home, isAdFree: false, room: nil))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .home, isAdFree: true, room: nil))
    }

    @Test
    func roomNotYetLoadedHidesAdsUntilLoaded() {
        // ルームが届くまでは購入者がいるか分からないので出さない（届いて購入者がいたら枠が消えてボタンが動くのを防ぐ）
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .room, isAdFree: false, room: nil))
        #expect(!AdDisplayPolicy.shouldShowAds(screen: .addCandidate, isAdFree: false, room: nil))
        // 届いて購入者がいなければ出す
        #expect(AdDisplayPolicy.shouldShowAds(screen: .room, isAdFree: false, room: Self.room()))
        #expect(AdDisplayPolicy.shouldShowAds(screen: .addCandidate, isAdFree: false, room: Self.room()))
    }

    // MARK: - 起動のしかた

    @Test
    func normalLaunchLoadsLiveAds() {
        let launch = LaunchContext(arguments: ["Dokogacha"], environment: [:])
        #expect(AdMode.make(launch: launch, adUnitID: Self.adUnitID) == .live(adUnitID: Self.adUnitID))
    }

    @Test
    func unitTestHostDisablesAds() {
        let launch = LaunchContext(arguments: ["Dokogacha"], environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        #expect(AdMode.make(launch: launch, adUnitID: Self.adUnitID) == .disabled)
    }

    @Test
    func uiTestingDisablesAds() {
        let launch = LaunchContext(arguments: ["Dokogacha", LaunchContext.uiTestingArgument], environment: [:])
        #expect(AdMode.make(launch: launch, adUnitID: Self.adUnitID) == .disabled)
    }

    @Test
    func screenshotDemoShowsPlaceholderWithoutLoading() {
        let launch = LaunchContext(arguments: ["Dokogacha", ScreenshotDemo.argument], environment: [:])
        let mode = AdMode.make(launch: launch, adUnitID: Self.adUnitID)
        #expect(mode == .placeholder)
        #expect(!mode.loadsAds)
    }

    @Test(arguments: [nil, ""])
    func missingAdUnitIDDisablesAds(adUnitID: String?) {
        let launch = LaunchContext(arguments: ["Dokogacha"], environment: [:])
        #expect(AdMode.make(launch: launch, adUnitID: adUnitID) == .disabled)
    }

    // MARK: - ATT

    @Test
    func asksTrackingOnlyWhenNotDeterminedWithLiveAds() {
        let live = AdMode.live(adUnitID: Self.adUnitID)
        #expect(AdTrackingPolicy.shouldRequestAuthorization(mode: live, status: .notDetermined, isAdFree: false))
        for status in [AdTrackingStatus.restricted, .denied, .authorized] {
            #expect(!AdTrackingPolicy.shouldRequestAuthorization(mode: live, status: status, isAdFree: false))
        }
    }

    @Test
    func neverAsksTrackingInTestsOrScreenshots() {
        for mode in [AdMode.disabled, .placeholder] {
            #expect(!AdTrackingPolicy.shouldRequestAuthorization(mode: mode, status: .notDetermined, isAdFree: false))
        }
    }

    @Test
    func purchaserIsNotAskedForTracking() {
        let live = AdMode.live(adUnitID: Self.adUnitID)
        #expect(!AdTrackingPolicy.shouldRequestAuthorization(mode: live, status: .notDetermined, isAdFree: true))
    }

    @Test
    func onlyAuthorizedGetsPersonalizedAds() {
        // F-50「拒否された場合は非パーソナライズ広告」。まだ尋ねていない・制限も非パーソナライズ
        #expect(AdTrackingPolicy.requestParameters(status: .authorized).isEmpty)
        for status in [AdTrackingStatus.notDetermined, .restricted, .denied] {
            #expect(AdTrackingPolicy.requestParameters(status: status) == ["npa": "1"])
        }
    }

    // MARK: - 読み込み直し

    @Test
    func bannerLoadsFirstTime() {
        let conditions = BannerLoadConditions(width: 361, requestParameters: ["npa": "1"])
        #expect(conditions.needsReload(since: nil))
    }

    @Test
    func bannerDoesNotReloadWithSameConditions() {
        let conditions = BannerLoadConditions(width: 361, requestParameters: ["npa": "1"])
        #expect(!conditions.needsReload(since: conditions))
    }

    @Test
    func bannerReloadsWhenWidthChanges() {
        let loaded = BannerLoadConditions(width: 361, requestParameters: ["npa": "1"])
        #expect(BannerLoadConditions(width: 402, requestParameters: ["npa": "1"]).needsReload(since: loaded))
    }

    @Test
    func bannerReloadsWhenTrackingIsAuthorized() {
        // ATT で「許可」したら、表示中のバナーも非パーソナライズ（npa=1）のリクエストのままにしない
        let loaded = BannerLoadConditions(width: 361, requestParameters: AdTrackingPolicy.requestParameters(status: .notDetermined))
        let authorized = BannerLoadConditions(width: 361, requestParameters: AdTrackingPolicy.requestParameters(status: .authorized))
        #expect(authorized.needsReload(since: loaded))
    }
}
