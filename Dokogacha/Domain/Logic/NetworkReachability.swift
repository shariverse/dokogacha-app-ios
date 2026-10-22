//
//  NetworkReachability.swift
//  Dokogacha
//
//  回線の状態の判定（02 の §9「オフライン」）。
//  `NWPathMonitor` の値をそのまま画面に持ち込まず、ここで値の型にしてから使う（Swift Testing で確かめるため）。
//

import Foundation

/// 回線の経路の状態（`NWPath.Status` を写したもの。Network の型をデータ層の外に出さないために持つ）。
nonisolated enum NetworkPathStatus: Equatable, Sendable {
    /// 使える経路がある
    case satisfied
    /// 使える経路が無い（機内モード・電波が無い・Wi-Fi に繋がっていないなど）
    case unsatisfied
    /// いまは無いが、接続を始めると経路ができうる（オンデマンドの VPN など）
    case requiresConnection
}

/// アプリから見た回線の状態。
///
/// 02 の §9: 閲覧は Firestore のキャッシュでできる。投稿・いいね・準備OK・抽選などはオンライン必須で、
/// オフラインのときは「オフラインです」のバナーを出す。
nonisolated enum NetworkReachability: Equatable, Sendable {
    /// まだ分からない（起動の直後に `NWPathMonitor` の最初の値が届く前）
    case unknown
    /// 繋がっている
    case online
    /// 繋がっていない
    case offline

    /// 経路の状態から決める。
    ///
    /// `requiresConnection` はオンラインとみなす。接続を始めれば経路ができるかもしれないので、操作を止めずに送らせる
    /// （送って通らなければ、いつもの通信エラーのトーストになる）
    init(pathStatus: NetworkPathStatus) {
        switch pathStatus {
        case .satisfied, .requiresConnection:
            self = .online
        case .unsatisfied:
            self = .offline
        }
    }

    /// 「オフラインです」のバナーを出すか（分からないうちは出さない。起動の直後にちらつかないように）
    var showsOfflineBanner: Bool {
        self == .offline
    }

    /// オンライン必須の操作（Callable Functions・いいね・準備OK）を送ってよいか。
    ///
    /// 分からないうちは送らせる（止めると、起動の直後に押したものが理由なく失敗するため）。
    /// オフラインと分かっているときだけ、送る前に止めてトーストを出す（送ると、Callable はタイムアウトまで待たされ、
    /// 直接の書き込みはキャッシュに書いたまま繋がるまで送られず、02 の §9 の「オンライン必須」を満たさない）
    var allowsOnlineOperations: Bool {
        self != .offline
    }

    /// オンライン必須の操作の前に確かめる。オフラインなら `AppError(.offline)` を投げる
    func requireOnline() throws(AppError) {
        guard allowsOnlineOperations else {
            throw AppError(.offline)
        }
    }
}
