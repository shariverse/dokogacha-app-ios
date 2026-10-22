//
//  TestClock.swift
//  DokogachaTests
//

import Foundation

/// テストで進められる時計。擬似のサーバーと画面の Model に同じ `read` を渡し、`advance(by:)` で時間がたったことにする
final class TestClock {
    /// 今の時刻
    var now: Date

    /// - Parameter now: 最初の時刻
    init(_ now: Date) {
        self.now = now
    }

    /// 今の時刻を読む処理（`clock` の引数に渡す。時計を持ち続けるが、時計は相手を持たないので循環しない）
    var read: () -> Date {
        { self.now }
    }

    /// 時間を進める
    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
