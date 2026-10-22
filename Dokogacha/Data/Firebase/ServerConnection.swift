//
//  ServerConnection.swift
//  Dokogacha
//

import Foundation

/// 起動時に決まる、サーバー（Firebase）への接続の状態。
///
/// 後続のデータ層は、この値を見て Firebase の Repository を使うか、擬似のサーバーを使うか、
/// 「サーバーに接続できない」表示にするかを決める。
nonisolated enum ServerConnection: Equatable, Sendable {
    /// まだ起動時の初期化をしていない（`ServerSession.start` の前）。設定漏れ（`unavailable`）と区別する
    case notStarted
    /// Firebase を初期化した（接続先は構成ごと）
    case firebase(FirebaseEnvironment)
    /// テスト・撮影のため、Firebase を初期化しなかった（メモリ上の擬似のサーバーで動かす）
    case disabled(DisabledReason)
    /// 設定が無い・読めないため、Firebase を初期化できなかった。アプリは落とさずに「サーバーに接続できない」状態で動かす
    case unavailable(UnavailableReason)

    /// Firebase を初期化しなかった理由
    nonisolated enum DisabledReason: Equatable, Sendable {
        /// Unit テストのホスト
        case unitTestHost
        /// UI テスト（`-uiTesting`）
        case uiTesting
        /// 撮影モード（`-screenshot-demo`）
        case screenshotDemo
    }

    /// Firebase を初期化できなかった理由
    nonisolated enum UnavailableReason: Equatable, Sendable {
        /// Info.plist の接続先が無い・知らない値（xcconfig の設定漏れ）
        case unknownEnvironment(String?)
        /// 読むはずの GoogleService-Info がアプリに入っていない（CI の Secrets が未登録・手元に置いていない）
        case missingOptionsFile(String?)
        /// GoogleService-Info はあるが、Firebase の設定として読めない
        case invalidOptionsFile(String)
    }

    /// Firebase の SDK を使ってよいか（初期化が済んでいるか）
    var isFirebaseConfigured: Bool {
        if case .firebase = self {
            return true
        }
        return false
    }
}
