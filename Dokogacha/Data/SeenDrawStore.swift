//
//  SeenDrawStore.swift
//  Dokogacha
//

import Foundation

/// この端末でガチャの演出（揺れ → カプセルの落下）を見終えた抽選を覚える（F-41「すでに見た抽選をもう一度再生しない」）。
///
/// 抽選の ID（`rooms.currentDrawId`）で覚える。ほかの人が回したことをルームの購読で知ったとき（S-07・S-13）に、
/// 見ていない抽選なら演出を自動で再生し、見た抽選なら再生せずにカプセルを出した状態にする。
/// 端末に覚えるだけなので、別の端末・入れ直したアプリでは、同じ抽選の演出をもう一度見ることがある（結果は同じ）。
protocol SeenDrawStore: AnyObject {
    /// 演出を見終えた抽選か
    func hasSeen(drawID: String) -> Bool
    /// 演出を見終えた抽選として覚える
    func markSeen(drawID: String)
}

/// `UserDefaults` に覚える `SeenDrawStore`（アプリを閉じても残す）。
///
/// 覚えるのは新しい順に `capacity` 件まで（ルームにつき抽選は引き直しを含めて 2 回までなので、古いものから捨ててよい）
final class UserDefaultsSeenDrawStore: SeenDrawStore {
    /// 覚えておく件数の上限
    static let capacity = 100
    /// `UserDefaults` の鍵
    static let key = "seenDrawIDs"

    private let defaults: UserDefaults

    /// - Parameter defaults: 覚える先（テストでは専用の suite を渡す）
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasSeen(drawID: String) -> Bool {
        storedIDs.contains(drawID)
    }

    func markSeen(drawID: String) {
        var ids = storedIDs.filter { $0 != drawID }
        ids.append(drawID)
        defaults.set(Array(ids.suffix(Self.capacity)), forKey: Self.key)
    }

    /// 覚えている抽選の ID（古い順）
    private var storedIDs: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}

/// メモリにだけ覚える `SeenDrawStore`（擬似のサーバー・Unit テスト・`-uiTesting` で、起動ごとに空から始める）
final class InMemorySeenDrawStore: SeenDrawStore {
    /// 覚えている抽選の ID
    private(set) var seenIDs: Set<String>

    /// - Parameter seenIDs: 初めから見たことにする抽選の ID
    init(seenIDs: Set<String> = []) {
        self.seenIDs = seenIDs
    }

    func hasSeen(drawID: String) -> Bool {
        seenIDs.contains(drawID)
    }

    func markSeen(drawID: String) {
        seenIDs.insert(drawID)
    }
}
