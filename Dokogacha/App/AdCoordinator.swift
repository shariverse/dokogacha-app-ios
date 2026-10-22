//
//  AdCoordinator.swift
//  Dokogacha
//

import Foundation
import Observation

/// 広告のまとめ役（F-50）。`AppDelegate` が 1 つ持ち、`DokoGachaApp` が `@Environment` で画面に渡す。
///
/// - 起動のしかたごとの扱い（`AdMode`）を持ち、本物の広告を読み込むときだけ SDK を初期化する（`start`）
/// - 画面は `shouldShowAds(on:room:)` でバナーを出すかを決める（`AdDisplayPolicy`）。自分が広告非表示を買ったか（`isAdFree`）は
///   起動の流れ（`RootView`）がプロフィールから入れる
/// - ATT は、ルームに入ったとき（`requestTrackingAuthorizationIfNeeded`）に、まだ尋ねていなければ尋ねる（`AdTrackingPolicy`）。
///   答えた後のバナーのリクエストは `requestParameters` で決める（拒否されたら非パーソナライズ）
@Observable
final class AdCoordinator {
    /// 広告ユニット ID を入れる Info.plist の鍵（値は xcconfig の `DG_BANNER_AD_UNIT_ID`）
    nonisolated static let adUnitIDInfoKey = "DGBannerAdUnitID"

    /// 起動のしかたごとの広告の扱い
    let mode: AdMode
    /// 自分が広告非表示を買ったか（`users.adFree` か端末の購入。`RootView` がプロフィールと端末の購入が替わるたびに入れ直す）
    var isAdFree = false
    /// いまの ATT の状態（尋ねたら更新する）
    private(set) var trackingStatus: AdTrackingStatus

    @ObservationIgnored private let service: any AdService
    /// 尋ねている途中の処理（ルームの画面を続けて開いても、ダイアログを 2 回出さない）
    @ObservationIgnored private var trackingRequest: Task<Void, Never>?

    /// - Parameters:
    ///   - mode: 起動のしかたごとの広告の扱い
    ///   - service: SDK と ATT の窓口（`mode` が広告を読み込まないときは呼ばない）
    init(mode: AdMode, service: any AdService) {
        self.mode = mode
        self.service = service
        trackingStatus = mode.loadsAds ? service.trackingStatus() : .notDetermined
    }

    /// 広告を使わないまとめ役（プレビュー・テスト）
    static var disabled: AdCoordinator {
        AdCoordinator(mode: .disabled, service: DisabledAdService())
    }

    /// 起動したとき。本物の広告を読み込むときだけ SDK を初期化する
    func start() {
        guard mode.loadsAds else {
            return
        }
        service.start()
    }

    /// その画面にバナーを出すか（`AdDisplayPolicy`）。広告を使わない起動（テスト）では常に出さない
    /// - Parameters:
    ///   - screen: 出そうとしている画面
    ///   - room: 開いているルーム（ホームでは nil）
    func shouldShowAds(on screen: AdScreen, room: Room?) -> Bool {
        guard mode != .disabled else {
            return false
        }
        return AdDisplayPolicy.shouldShowAds(screen: screen, isAdFree: isAdFree, room: room)
    }

    /// バナーのリクエストに足すパラメータ（ATT で許可した人だけパーソナライズ）
    var requestParameters: [String: String] {
        AdTrackingPolicy.requestParameters(status: trackingStatus)
    }

    /// ルームに入ったとき。まだ尋ねていなければ ATT の許可を尋ねる（尋ねている途中なら、その終わりを待つ）
    func requestTrackingAuthorizationIfNeeded() async {
        if let trackingRequest {
            await trackingRequest.value
            return
        }
        // ほかの画面（設定など）で状態が変わっていることがあるので、尋ねる前に読み直す
        if mode.loadsAds {
            trackingStatus = service.trackingStatus()
        }
        guard AdTrackingPolicy.shouldRequestAuthorization(mode: mode, status: trackingStatus, isAdFree: isAdFree) else {
            return
        }
        let service = service
        let task = Task { [weak self] in
            let status = await service.requestTrackingAuthorization()
            self?.trackingStatus = status
        }
        trackingRequest = task
        await task.value
        trackingRequest = nil
    }
}
