//
//  GoogleMobileAdsService.swift
//  Dokogacha
//

import AppTrackingTransparency
@preconcurrency import GoogleMobileAds

/// Google Mobile Ads の初期化と ATT の `AdService`（SDK に触るのはここと `GoogleBannerAdView` だけ）
struct GoogleMobileAdsService: AdService {
    func start() {
        // 初期化の結果（アダプタの状態）は使わない。終わる前に読み込んだバナーも、SDK が初期化を待ってから読み込む
        MobileAds.shared.start(completionHandler: nil)
    }

    func trackingStatus() -> AdTrackingStatus {
        Self.status(ATTrackingManager.trackingAuthorizationStatus)
    }

    func requestTrackingAuthorization() async -> AdTrackingStatus {
        Self.status(await ATTrackingManager.requestTrackingAuthorization())
    }

    /// OS の状態を写す（将来増えた値は、許可していないものとして扱う）
    private static func status(_ status: ATTrackingManager.AuthorizationStatus) -> AdTrackingStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .authorized
        @unknown default:
            .denied
        }
    }
}
