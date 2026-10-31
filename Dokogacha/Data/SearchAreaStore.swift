//
//  SearchAreaStore.swift
//  Dokogacha
//

import Foundation

/// S-08 で選んだ検索のエリア（全国・地方・都道府県・市区町村）を覚える（次に S-08 を開いたときも同じエリアで探す。Issue #131・#160）。
///
/// 端末に覚えるだけで、サーバーには送らない。アカウントに結び付く値ではない（端末の設定）ので、
/// アカウントを削除しても忘れない（`AccountDeviceData` で消さない）
protocol SearchAreaStore: AnyObject {
    /// 覚えているエリア（まだ選んでいなければ `DomainConstants.SearchRegion.initialScope`）
    var scope: SearchScope { get }
    /// エリアを覚える
    func save(_ scope: SearchScope)
}

/// `UserDefaults` に覚える `SearchAreaStore`（アプリを閉じても残す）。
///
/// 地方の rawValue（`key`。Issue #131 から同じ鍵と値）に、都道府県コード（`prefectureKey`）・市区町村の団体コード（`municipalityKey`）を
/// 足して覚える。地方だけを覚えている端末（#131 の版）では、その地方全体を選んだ状態で開く。
/// 覚えた値が知らない地方なら、まだ選んでいないとみなす。都道府県・市区町村が合わなければ、合うところまでにする（`SearchScope.restored`）
final class UserDefaultsSearchAreaStore: SearchAreaStore {
    /// 地方（`SearchArea` の rawValue）の `UserDefaults` の鍵
    static let key = "placeSearchArea"
    /// 都道府県コードの `UserDefaults` の鍵（地方全体のときは無い）
    static let prefectureKey = "placeSearchPrefecture"
    /// 市区町村の団体コードの `UserDefaults` の鍵（都道府県全体のときは無い）
    static let municipalityKey = "placeSearchMunicipality"

    private let defaults: UserDefaults
    private let catalog: MunicipalityCatalog

    /// - Parameters:
    ///   - defaults: 覚える先（テストでは専用の suite を渡す）
    ///   - catalog: 市区町村の一覧（覚えた団体コードを市区町村に戻す）
    init(defaults: UserDefaults = .standard, catalog: MunicipalityCatalog = .bundled) {
        self.defaults = defaults
        self.catalog = catalog
    }

    var scope: SearchScope {
        SearchScope.restored(
            areaRawValue: defaults.string(forKey: Self.key),
            prefectureCode: defaults.object(forKey: Self.prefectureKey) as? Int,
            municipalityCode: defaults.string(forKey: Self.municipalityKey),
            catalog: catalog,
            fallback: DomainConstants.SearchRegion.initialScope
        )
    }

    func save(_ scope: SearchScope) {
        defaults.set(scope.area.rawValue, forKey: Self.key)
        if let prefecture = scope.prefecture {
            defaults.set(prefecture.code, forKey: Self.prefectureKey)
        } else {
            defaults.removeObject(forKey: Self.prefectureKey)
        }
        if let municipality = scope.municipality {
            defaults.set(municipality.code, forKey: Self.municipalityKey)
        } else {
            defaults.removeObject(forKey: Self.municipalityKey)
        }
    }
}

/// メモリにだけ覚える `SearchAreaStore`（擬似のサーバー・Unit テスト・`-uiTesting`・撮影モードで、起動ごとに初めのエリアから始める）
final class InMemorySearchAreaStore: SearchAreaStore {
    private(set) var scope: SearchScope

    /// - Parameter scope: 初めに覚えておくエリア
    init(scope: SearchScope = DomainConstants.SearchRegion.initialScope) {
        self.scope = scope
    }

    func save(_ scope: SearchScope) {
        self.scope = scope
    }
}
