//
//  SearchScope.swift
//  Dokogacha
//

import Foundation

/// S-08 で選んでいる検索のエリア（全国・地方・都道府県・市区町村。03 の S-08 の 6・Issue #131・#160）。
///
/// 地方 → 都道府県 → 市区町村の順に絞る。市区町村は任意で、選ばなければ都道府県全体で探す。
/// 地方に都道府県が 1 つだけの北海道・沖縄は、地方を選べば都道府県も選んだことになり、次は市区町村を選べる。
/// 作るときに段のつじつまを合わせる（市区町村を選べば、その都道府県と地方も決まる）ので、食い違った値は作れない
nonisolated struct SearchScope: Hashable, Sendable {
    /// どの段まで絞っているか
    enum Level: Sendable {
        /// 全国
        case nationwide
        /// 地方全体（北海道・沖縄は都道府県全体と同じ）
        case area
        /// 都道府県全体
        case prefecture
        /// 市区町村
        case municipality
    }

    /// 全国
    static let nationwide = Self(area: .nationwide)

    /// 地方（全国を含む）
    let area: SearchArea
    /// 都道府県（地方全体なら nil。北海道・沖縄は地方を選べば入る）
    let prefecture: Prefecture?
    /// 市区町村（都道府県全体なら nil）
    let municipality: Municipality?

    /// 地方全体（北海道・沖縄は、その都道府県全体）
    init(area: SearchArea) {
        self.area = area
        prefecture = area.soloPrefecture
        municipality = nil
    }

    /// 都道府県全体
    init(prefecture: Prefecture) {
        area = prefecture.area
        self.prefecture = prefecture
        municipality = nil
    }

    /// 市区町村。団体コードの都道府県が分からなければ nil
    init?(municipality: Municipality) {
        guard let prefecture = municipality.prefecture else {
            return nil
        }
        area = prefecture.area
        self.prefecture = prefecture
        self.municipality = municipality
    }

    /// どの段まで絞っているか
    var level: Level {
        if municipality != nil {
            .municipality
        } else if prefecture != nil, area.soloPrefecture == nil {
            .prefecture
        } else if area != .nationwide {
            .area
        } else {
            .nationwide
        }
    }

    /// 一段上（市区町村 → 都道府県全体、都道府県 → 地方全体、地方 → 全国）。全国は nil
    var parent: Self? {
        switch level {
        case .municipality: prefecture.map(Self.init(prefecture:))
        case .prefecture: Self(area: area)
        case .area: .nationwide
        case .nationwide: nil
        }
    }

    /// 市区町村を選べるか（都道府県が決まっているとき）
    var canPickMunicipality: Bool {
        prefecture != nil
    }

    /// 検索の範囲。市区町村は都道府県の矩形（MapKit の検索では、市区町村の範囲を住所の検索で引いて狭める）
    var bounds: SearchBounds {
        prefecture?.bounds ?? area.bounds
    }

    /// 検索の結果を、このエリアの結果として残すか。
    ///
    /// - 全国: すべて残す（範囲の矩形だけで絞る）
    /// - 都道府県が分かる結果: 地方なら地方の都道府県、都道府県・市区町村ならその都道府県のときだけ残す。
    ///   市区町村は、さらに `locality` などが市区町村の名前に合うときだけ残す（`PlaceLocality.matches`）
    /// - 都道府県・市区町村が分からない（無い・英語の名前など）: 座標が検索した範囲に入るときだけ残す（iOS 17 では範囲の外の結果も届くため）
    /// - Parameters:
    ///   - hit: MapKit の検索結果から取り出した値
    ///   - searchedBounds: 検索した範囲（市区町村は MapKit で引いた範囲。引けなければ `bounds`）
    func keeps(_ hit: PlaceSearchHit, searchedIn searchedBounds: SearchBounds) -> Bool {
        guard area != .nationwide else {
            return true
        }
        let isInside = searchedBounds.contains(latitude: hit.latitude, longitude: hit.longitude)
        guard let hitPrefecture = Prefecture.named(hit.administrativeArea) else {
            return isInside
        }
        guard prefecture.map({ hitPrefecture == $0 }) ?? (hitPrefecture.area == area) else {
            return false
        }
        guard let municipality else {
            return true
        }
        return PlaceLocality.matches(locality: hit.locality, subLocality: hit.subLocality, municipality: municipality.name) ?? isInside
    }

    /// 端末に覚えた値から戻す（`SearchAreaStore`）。
    ///
    /// 地方の rawValue（Issue #131 から覚えている値）だけなら、その地方全体。都道府県・市区町村のコードが、覚えた地方・都道府県と
    /// 合わない・一覧に無い（合併などで無くなった）ときは、合うところまでで止める。地方が知らない値なら `fallback`
    /// - Parameters:
    ///   - areaRawValue: 地方（`SearchArea` の rawValue）
    ///   - prefectureCode: 都道府県コード
    ///   - municipalityCode: 市区町村の団体コード
    ///   - catalog: 市区町村の一覧
    ///   - fallback: 地方が無い・知らない値のときのエリア
    static func restored(
        areaRawValue: String?,
        prefectureCode: Int?,
        municipalityCode: String?,
        catalog: MunicipalityCatalog,
        fallback: Self
    ) -> Self {
        guard let area = areaRawValue.flatMap(SearchArea.init(rawValue:)) else {
            return fallback
        }
        guard let prefecture = area.soloPrefecture ?? prefectureCode.flatMap(Prefecture.code), prefecture.area == area else {
            return Self(area: area)
        }
        guard
            let municipality = municipalityCode.flatMap(catalog.municipality(code:)),
            municipality.prefectureCode == prefecture.code,
            let scope = Self(municipality: municipality)
        else {
            return Self(prefecture: prefecture)
        }
        return scope
    }
}
