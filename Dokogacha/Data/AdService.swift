//
//  AdService.swift
//  Dokogacha
//

import Foundation

/// 広告の SDK（Google Mobile Ads）と ATT（`ATTrackingManager`）の窓口。テストでは差し替えて、初期化と尋ねる時機を確かめる
protocol AdService {
    /// SDK を初期化する（起動時に一度だけ）
    func start()
    /// いまの ATT の状態
    func trackingStatus() -> AdTrackingStatus
    /// ATT の許可を尋ね、答えた後の状態を返す（アプリが前面に出ていないと OS はダイアログを出さず、`notDetermined` のまま返る）
    func requestTrackingAuthorization() async -> AdTrackingStatus
}

/// 広告を使わないときの窓口（何もしない）
struct DisabledAdService: AdService {
    func start() {}

    func trackingStatus() -> AdTrackingStatus {
        .notDetermined
    }

    func requestTrackingAuthorization() async -> AdTrackingStatus {
        .notDetermined
    }
}
