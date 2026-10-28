//
//  SearchAreaStore.swift
//  Dokogacha
//

import Foundation

/// S-08 で選んだ検索のエリアを覚える（次に S-08 を開いたときも同じエリアで探す。Issue #131）。
///
/// 端末に覚えるだけで、サーバーには送らない。アカウントに結び付く値ではない（端末の設定）ので、
/// アカウントを削除しても忘れない（`AccountDeviceData` で消さない）
protocol SearchAreaStore: AnyObject {
    /// 覚えているエリア（まだ選んでいなければ `DomainConstants.SearchRegion.initialArea`）
    var area: SearchArea { get }
    /// エリアを覚える
    func save(_ area: SearchArea)
}

/// `UserDefaults` に覚える `SearchAreaStore`（アプリを閉じても残す）。覚えた値が知らないエリアなら、まだ選んでいないとみなす
final class UserDefaultsSearchAreaStore: SearchAreaStore {
    /// `UserDefaults` の鍵
    static let key = "placeSearchArea"

    private let defaults: UserDefaults

    /// - Parameter defaults: 覚える先（テストでは専用の suite を渡す）
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var area: SearchArea {
        defaults.string(forKey: Self.key).flatMap(SearchArea.init(rawValue:)) ?? DomainConstants.SearchRegion.initialArea
    }

    func save(_ area: SearchArea) {
        defaults.set(area.rawValue, forKey: Self.key)
    }
}

/// メモリにだけ覚える `SearchAreaStore`（擬似のサーバー・Unit テスト・`-uiTesting`・撮影モードで、起動ごとに初めのエリアから始める）
final class InMemorySearchAreaStore: SearchAreaStore {
    private(set) var area: SearchArea

    /// - Parameter area: 初めに覚えておくエリア
    init(area: SearchArea = DomainConstants.SearchRegion.initialArea) {
        self.area = area
    }

    func save(_ area: SearchArea) {
        self.area = area
    }
}
