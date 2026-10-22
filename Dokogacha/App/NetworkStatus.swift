//
//  NetworkStatus.swift
//  Dokogacha
//

import Foundation
import Observation

/// 端末の回線の状態（02 の §9 のオフライン）。`AppDelegate` が 1 つ持ち、`DokoGachaApp` が `@Environment` で画面に渡す。
///
/// - 画面は `reachability.showsOfflineBanner` で「オフラインです」のバナーを出す（`OfflineBannerModifier`）
/// - データ層の窓口（`OnlineRequiredFunctionsClient`・`OnlineRequiredRoomRepository`）は、送る前に `requireOnline()` で確かめ、
///   オフラインなら送らずに `AppError(.offline)` を投げる（画面はいつものトーストで出す）
/// - 起動の流れ（`RootModel`）は、オフラインのまま読み込み中・失敗のときに、その旨を出して繋がったらやり直す
@Observable
final class NetworkStatus {
    /// いまの回線の状態
    private(set) var reachability: NetworkReachability

    /// 監視の購読（持ち主の寿命で止める）
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// - Parameter reachability: 監視を始める前の状態（既定は「分からない」。テストでは決めた値を渡す）
    init(reachability: NetworkReachability = .unknown) {
        self.reachability = reachability
    }

    deinit {
        observation?.cancel()
    }

    /// 経路の監視を始める（2 回目以降は前の監視を止めて替える）
    func start(monitor: any NetworkPathMonitoring) {
        observation?.cancel()
        let statuses = monitor.statuses()
        observation = Task { [weak self] in
            for await status in statuses {
                guard let self else {
                    return
                }
                let reachability = NetworkReachability(pathStatus: status)
                // 同じ値が続けて届いても画面に知らせない
                if self.reachability != reachability {
                    self.reachability = reachability
                }
            }
        }
    }

    /// オフラインか（バナーを出すか）
    var isOffline: Bool {
        reachability.showsOfflineBanner
    }

    /// オンライン必須の操作の前に確かめる。オフラインなら `AppError(.offline)` を投げる
    func requireOnline() throws(AppError) {
        try reachability.requireOnline()
    }

    /// 起動のしかたから、監視する窓口を選ぶ。
    ///
    /// Unit テストのホスト・`-uiTesting`・撮影モードは、本物の回線を見ずに決めた状態にする（`-network-offline` ならオフライン）
    static func monitor(for launch: LaunchContext) -> any NetworkPathMonitoring {
        if launch.isUnitTestHost || launch.isUITesting || launch.isScreenshotDemo {
            return FixedNetworkPathMonitor(status: launch.networkOffline ? .unsatisfied : .satisfied)
        }
        return SystemNetworkPathMonitor()
    }
}
