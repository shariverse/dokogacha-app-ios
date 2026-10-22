//
//  AsyncTestSupport.swift
//  DokogachaTests
//

import Foundation

/// 非同期のテストの道具。固定の時間で待たず、MainActor のほかの処理に順番を譲りながら条件を待つ
enum AsyncTestSupport {
    /// 条件が満たされるまで、ほかの処理に順番を譲る（`Task.yield`）。満たされたら true。
    ///
    /// `onTermination` から MainActor に戻ってリスナーを外す処理などを待つのに使う。時間では待たないので、
    /// Mac が混んでいても揺らがない（譲る回数の上限に達したら false）
    static func eventually(maxYields: Int = 10_000, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<maxYields {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}
