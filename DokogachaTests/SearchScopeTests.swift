//
//  SearchScopeTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 で選んでいる検索のエリア（`SearchScope`）を確かめる: 段のつじつま・一段上・結果を残すかの判定・覚えた値の戻し方（Issue #131・#160）
struct SearchScopeTests {
    /// 都道府県
    static func prefecture(_ code: Int) throws -> Prefecture {
        try #require(Prefecture.code(code))
    }

    /// 市区町村のエリア
    static func municipality(_ code: String) throws -> SearchScope {
        let municipality = try #require(MunicipalityCatalog.bundled.municipality(code: code))
        return try #require(SearchScope(municipality: municipality))
    }

    /// MapKit の結果の写し（既定は東京駅の近く）
    static func hit(
        _ administrativeArea: String?,
        locality: String? = nil,
        subLocality: String? = nil,
        latitude: Double = 35.68,
        longitude: Double = 139.77
    ) -> PlaceSearchHit {
        PlaceSearchHit(
            name: "場所",
            administrativeArea: administrativeArea,
            locality: locality,
            subLocality: subLocality,
            latitude: latitude,
            longitude: longitude,
            mapItemID: nil,
            pointOfInterestCategory: nil
        )
    }

    // MARK: - 段

    /// 市区町村を選べば、その都道府県と地方も決まる。北海道・沖縄は、地方を選べば都道府県も決まる
    @Test
    func levelsAreConsistent() throws {
        let toshima = try Self.municipality("131164")
        #expect(toshima.area == .kanto)
        #expect(toshima.prefecture?.code == 13)
        #expect(toshima.level == .municipality)

        #expect(SearchScope(prefecture: try Self.prefecture(13)).level == .prefecture)
        #expect(SearchScope(area: .kanto).level == .area)
        #expect(SearchScope(area: .kanto).prefecture == nil)
        #expect(SearchScope.nationwide.level == .nationwide)

        let hokkaido = SearchScope(area: .hokkaido)
        #expect(hokkaido.level == .area)
        #expect(hokkaido.prefecture?.name == "北海道")
        #expect(hokkaido.canPickMunicipality)
        #expect(SearchScope(prefecture: try Self.prefecture(1)) == hokkaido)
        #expect(!SearchScope(area: .kanto).canPickMunicipality)
    }

    /// 一段上は、市区町村 → 都道府県全体 → 地方全体 → 全国。北海道の市区町村は、北海道全体の次が全国
    @Test
    func parentsGoUpOneLevel() throws {
        let tokyo = SearchScope(prefecture: try Self.prefecture(13))
        #expect(try Self.municipality("131164").parent == tokyo)
        #expect(tokyo.parent == SearchScope(area: .kanto))
        #expect(SearchScope(area: .kanto).parent == .nationwide)
        #expect(SearchScope.nationwide.parent == nil)

        let sapporo = try Self.municipality("011002")
        #expect(sapporo.parent == SearchScope(area: .hokkaido))
        #expect(sapporo.parent?.parent == .nationwide)
    }

    /// 検索の範囲は、都道府県まで絞れば都道府県の矩形、地方なら地方の矩形（市区町村は都道府県の矩形から MapKit で狭める）
    @Test
    func boundsFollowNarrowestKnownLevel() throws {
        let tokyo = try Self.prefecture(13)
        #expect(SearchScope(area: .kanto).bounds == SearchArea.kanto.bounds)
        #expect(SearchScope(prefecture: tokyo).bounds == tokyo.bounds)
        #expect(try Self.municipality("131164").bounds == tokyo.bounds)
        #expect(SearchScope.nationwide.bounds == SearchArea.nationwide.bounds)
    }

    // MARK: - 結果を残すか

    /// 全国はすべての結果を残す
    @Test
    func nationwideKeepsEverything() {
        let bounds = SearchScope.nationwide.bounds
        #expect(SearchScope.nationwide.keeps(Self.hit("大阪府"), searchedIn: bounds))
        #expect(SearchScope.nationwide.keeps(Self.hit(nil, latitude: 37.5, longitude: 127.0), searchedIn: bounds))
    }

    /// 地方は、都道府県が分かれば地方の都道府県だけを残す（矩形に入る隣の地方の結果も取り除く）
    @Test
    func areaKeepsOnlyItsPrefectures() {
        let kanto = SearchScope(area: .kanto)
        let chubu = SearchScope(area: .chubu)
        #expect(kanto.keeps(Self.hit("東京都"), searchedIn: kanto.bounds))
        #expect(kanto.keeps(Self.hit("東京"), searchedIn: kanto.bounds))
        // 中部の矩形に入る埼玉県・群馬県の結果は、中部では取り除く
        #expect(!chubu.keeps(Self.hit("埼玉県", latitude: 36.0, longitude: 139.4), searchedIn: chubu.bounds))
        #expect(!chubu.keeps(Self.hit("群馬県", latitude: 36.4, longitude: 139.0), searchedIn: chubu.bounds))
        #expect(!kanto.keeps(Self.hit("大阪府", latitude: 34.69, longitude: 135.50), searchedIn: kanto.bounds))
    }

    /// 都道府県は、その都道府県の結果だけを残す。英語の端末のローマ字の都道府県も当てる
    @Test
    func prefectureKeepsOnlyItself() throws {
        let tokyo = SearchScope(prefecture: try Self.prefecture(13))
        #expect(tokyo.keeps(Self.hit("東京都", locality: "渋谷区"), searchedIn: tokyo.bounds))
        #expect(tokyo.keeps(Self.hit("Tokyo", locality: "Shibuya"), searchedIn: tokyo.bounds))
        // 東京の矩形に入る神奈川県・埼玉県の結果
        #expect(!tokyo.keeps(Self.hit("神奈川県", locality: "川崎市", latitude: 35.53, longitude: 139.70), searchedIn: tokyo.bounds))
        #expect(!tokyo.keeps(Self.hit("Saitama", latitude: 35.86, longitude: 139.65), searchedIn: tokyo.bounds))
    }

    /// 市区町村は、`locality` などが市区町村の名前に合う結果だけを残す（政令指定都市の区・郡の町村の形を含む）
    @Test
    func municipalityKeepsOnlyMatchingLocality() throws {
        let yokohama = try Self.municipality("141003")
        let hakone = try Self.municipality("143821")
        let toshima = try Self.municipality("131164")
        #expect(yokohama.keeps(Self.hit("神奈川県", locality: "中区, 横浜市"), searchedIn: yokohama.bounds))
        #expect(yokohama.keeps(Self.hit("神奈川県", locality: "横浜市", subLocality: "金沢区"), searchedIn: yokohama.bounds))
        #expect(!yokohama.keeps(Self.hit("神奈川県", locality: "川崎区, 川崎市"), searchedIn: yokohama.bounds))
        #expect(hakone.keeps(Self.hit("神奈川県", locality: "足柄下郡箱根町"), searchedIn: hakone.bounds))
        #expect(hakone.keeps(Self.hit("神奈川県", locality: "足柄下郡", subLocality: "箱根町"), searchedIn: hakone.bounds))
        #expect(!hakone.keeps(Self.hit("神奈川県", locality: "足柄下郡", subLocality: "真鶴町"), searchedIn: hakone.bounds))
        // 別の都道府県の結果は、市区町村の名前が同じでも取り除く（東京の北区と札幌市北区のように、同じ名前の区がある）
        #expect(!toshima.keeps(Self.hit("北海道", locality: "豊島区"), searchedIn: toshima.bounds))
        #expect(!toshima.keeps(Self.hit("東京都", locality: "練馬区"), searchedIn: toshima.bounds))
    }

    /// 市区町村が分からない（無い・英語の名前）・都道府県が分からないときは、座標が検索した範囲に入るかで決める
    @Test
    func unknownLocalityFallsBackToSearchedBounds() throws {
        let toshima = try Self.municipality("131164")
        let searched = SearchBounds(latitude: 35.71...35.75, longitude: 139.68...139.75)
        #expect(toshima.keeps(Self.hit("東京都", locality: nil, latitude: 35.73, longitude: 139.71), searchedIn: searched))
        #expect(toshima.keeps(Self.hit("Tokyo", locality: "Toshima", latitude: 35.73, longitude: 139.71), searchedIn: searched))
        #expect(!toshima.keeps(Self.hit("Tokyo", locality: "Shibuya", latitude: 35.66, longitude: 139.70), searchedIn: searched))
        #expect(toshima.keeps(Self.hit(nil, latitude: 35.73, longitude: 139.71), searchedIn: searched))
        #expect(!toshima.keeps(Self.hit(nil, latitude: 34.69, longitude: 135.50), searchedIn: searched))
    }

    // MARK: - 覚えた値から戻す

    /// 地方・都道府県・市区町村のコードから戻す。#131 の版の地方だけの値は、その地方全体
    @Test
    func restoresFromStoredValues() throws {
        let catalog = MunicipalityCatalog.bundled
        func restored(_ area: String?, _ prefecture: Int? = nil, _ municipality: String? = nil) -> SearchScope {
            SearchScope.restored(
                areaRawValue: area,
                prefectureCode: prefecture,
                municipalityCode: municipality,
                catalog: catalog,
                fallback: .nationwide
            )
        }
        #expect(restored("kanto") == SearchScope(area: .kanto))
        #expect(restored("kanto", 13) == SearchScope(prefecture: try Self.prefecture(13)))
        #expect(restored("kanto", 13, "131164") == (try Self.municipality("131164")))
        #expect(restored("hokkaido", nil, "011002") == (try Self.municipality("011002")))
        #expect(restored(nil) == .nationwide)
        #expect(restored("tokai", 13) == .nationwide)
    }

    /// 段が合わない値（地方と都道府県が違う・無くなった市区町村・別の都道府県の市区町村）は、合うところまでにする
    @Test
    func restoresUpToConsistentLevel() throws {
        let catalog = MunicipalityCatalog.bundled
        func restored(_ area: String, _ prefecture: Int?, _ municipality: String?) -> SearchScope {
            SearchScope.restored(
                areaRawValue: area,
                prefectureCode: prefecture,
                municipalityCode: municipality,
                catalog: catalog,
                fallback: .nationwide
            )
        }
        #expect(restored("kansai", 13, nil) == SearchScope(area: .kansai))
        #expect(restored("kanto", 99, nil) == SearchScope(area: .kanto))
        #expect(restored("kanto", 13, "999999") == SearchScope(prefecture: try Self.prefecture(13)))
        #expect(restored("kanto", 13, "141003") == SearchScope(prefecture: try Self.prefecture(13)))
    }
}
