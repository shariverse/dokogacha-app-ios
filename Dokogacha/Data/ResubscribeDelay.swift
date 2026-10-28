//
//  ResubscribeDelay.swift
//  Dokogacha
//

import Foundation

/// 購読が失敗で終わったとき、やり直すまでの待ち方。
///
/// 画面を出している間に購読が一時的に失敗しても（通信の揺らぎ・サーバーの一時的な拒否）、画面は前の値のまま残し、
/// 少し待ってから購読し直す。すぐにやり直すと、失敗が続くときにサーバーへ問い合わせ続けるので間を置く。
/// テストでは待たずに進める `sleep` に差し替える（固定の時間で待たない）。
nonisolated struct ResubscribeDelay: Sendable {
    /// 待つ処理の型
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// やり直すまでに待つ時間（アプリで決めた値。仕様には無い）
    static let standardDelay: Duration = .seconds(5)

    /// 既定（5 秒待つ）
    static let standard = Self(delay: standardDelay) { try await Task.sleep(for: $0) }

    /// やり直すまでに待つ時間
    let delay: Duration
    /// 待つ処理
    let sleep: Sleep

    /// 待つ。待っている間に cancel されたら（画面が消えた）false を返し、やり直さない
    func wait() async -> Bool {
        do {
            try await sleep(delay)
        } catch {
            return false
        }
        return !Task.isCancelled
    }
}
