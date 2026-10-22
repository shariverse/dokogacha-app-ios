//
//  NetworkPathMonitor.swift
//  Dokogacha
//

import Foundation
import Network

/// 回線の経路の状態を流す窓口（02 の §9 のオフライン）。
///
/// 本物は `NWPathMonitor`。Unit テストのホスト・`-uiTesting`・撮影モードでは、起動引数で決めた固定の状態を流すものに差し替える
/// （Simulator の回線をテストから切れないため。`LaunchContext.networkOffline`）。
protocol NetworkPathMonitoring: Sendable {
    /// 経路の状態を、変わるたびに流す（最初に今の状態を流す）。購読をやめたら監視を止める
    func statuses() -> AsyncStream<NetworkPathStatus>
}

/// `NWPathMonitor` で経路の状態を流す
nonisolated struct SystemNetworkPathMonitor: NetworkPathMonitoring {
    func statuses() -> AsyncStream<NetworkPathStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: NetworkPathStatus.self, bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            continuation.yield(Self.status(of: path.status))
        }
        continuation.onTermination = { _ in
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "jp.shilokuma.Dokogacha.network-path"))
        return stream
    }

    /// Network の状態をアプリの値にする（知らない値は「使える」とみなし、操作を止めない）
    private static func status(of status: NWPath.Status) -> NetworkPathStatus {
        switch status {
        case .satisfied:
            .satisfied
        case .unsatisfied:
            .unsatisfied
        case .requiresConnection:
            .requiresConnection
        @unknown default:
            .satisfied
        }
    }
}

/// 決まった状態を 1 回だけ流す（Unit テストのホスト・`-uiTesting`・撮影モード・プレビュー）
nonisolated struct FixedNetworkPathMonitor: NetworkPathMonitoring {
    /// 流す状態
    let status: NetworkPathStatus

    func statuses() -> AsyncStream<NetworkPathStatus> {
        AsyncStream { continuation in
            continuation.yield(status)
            continuation.finish()
        }
    }
}
