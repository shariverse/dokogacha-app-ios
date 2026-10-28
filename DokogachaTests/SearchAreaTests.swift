//
//  SearchAreaTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の検索のエリア（`SearchArea`）を確かめる: 地方の矩形に主な都市が入る・都道府県の分け方・結果を残すかの判定（Issue #131）
struct SearchAreaTests {
    /// 地方の主な都市・端の町
    nonisolated struct City: Sendable, CustomTestStringConvertible {
        let area: SearchArea
        let name: String
        let latitude: Double
        let longitude: Double

        var testDescription: String {
            name
        }

        init(_ area: SearchArea, _ name: String, _ latitude: Double, _ longitude: Double) {
            self.area = area
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// 地方ごとの主な都市と端の町（緯度・経度）。矩形に入らないと、その地方を選んでも見つからない
    nonisolated static let cities: [City] = [
        City(.hokkaido, "札幌", 43.06, 141.35),
        City(.hokkaido, "函館", 41.77, 140.73),
        City(.hokkaido, "稚内", 45.42, 141.67),
        City(.tohoku, "仙台", 38.27, 140.87),
        City(.tohoku, "青森", 40.82, 140.74),
        City(.tohoku, "いわき", 37.05, 140.89),
        City(.kanto, "東京", 35.68, 139.77),
        City(.kanto, "宇都宮", 36.56, 139.88),
        City(.kanto, "館山", 34.99, 139.87),
        City(.chubu, "名古屋", 35.18, 136.91),
        City(.chubu, "新潟", 37.92, 139.04),
        City(.chubu, "金沢", 36.56, 136.66),
        City(.chubu, "静岡", 34.98, 138.38),
        City(.chubu, "敦賀", 35.65, 136.06),
        City(.chubu, "熱海", 35.10, 139.07),
        City(.kansai, "大阪", 34.69, 135.50),
        City(.kansai, "京都", 35.01, 135.77),
        City(.kansai, "神戸", 34.69, 135.20),
        City(.kansai, "伊勢", 34.49, 136.71),
        City(.kansai, "白浜", 33.68, 135.35),
        City(.chugokuShikoku, "広島", 34.39, 132.46),
        City(.chugokuShikoku, "鳥取", 35.50, 134.24),
        City(.chugokuShikoku, "松山", 33.84, 132.77),
        City(.chugokuShikoku, "高知", 33.56, 133.53),
        City(.chugokuShikoku, "下関", 33.96, 130.94),
        City(.kyushu, "福岡", 33.59, 130.40),
        City(.kyushu, "鹿児島", 31.60, 130.56),
        City(.kyushu, "長崎", 32.75, 129.88),
        City(.kyushu, "大分", 33.24, 131.61),
        City(.okinawa, "那覇", 26.21, 127.68),
        City(.okinawa, "石垣", 24.34, 124.16),
        City(.okinawa, "宮古島", 24.80, 125.28)
    ]

    /// 地方の名前（都道府県）で作った MapKit の結果の写し
    static func hit(_ administrativeArea: String?, latitude: Double = 35.68, longitude: Double = 139.77) -> PlaceSearchHit {
        PlaceSearchHit(
            name: "場所",
            administrativeArea: administrativeArea,
            locality: nil,
            latitude: latitude,
            longitude: longitude,
            mapItemID: nil,
            pointOfInterestCategory: nil
        )
    }

    /// 地方の矩形に、その地方の主な都市と端の町が入る
    @Test(arguments: Self.cities)
    func areaBoundsContainCities(city: City) {
        #expect(city.area.bounds.contains(latitude: city.latitude, longitude: city.longitude), "\(city.name) が \(city.area) の範囲の外")
    }

    /// 地方の矩形は、全国の矩形の中にある
    @Test(arguments: SearchArea.allCases)
    func areaBoundsAreInsideNationwide(area: SearchArea) {
        let nationwide = SearchArea.nationwide.bounds
        let bounds = area.bounds
        #expect(nationwide.contains(latitude: bounds.minLatitude, longitude: bounds.minLongitude))
        #expect(nationwide.contains(latitude: bounds.maxLatitude, longitude: bounds.maxLongitude))
    }

    /// 地方の都道府県は、47 の都道府県を重ならずに 1 回ずつ持つ。全国は都道府県で絞らない
    @Test
    func prefecturesCoverJapanOnce() {
        let prefectures = SearchArea.allPrefectures
        #expect(prefectures.count == 47)
        #expect(Set(prefectures).count == 47)
        #expect(SearchArea.nationwide.prefectures == nil)
        #expect(SearchArea.allCases.filter { $0 != .nationwide }.allSatisfy { !($0.prefectures ?? []).isEmpty })
    }

    /// 都道府県の名前は「都」「府」「県」が無くても当て、都道府県でないものは nil
    @Test
    func prefectureNames() {
        #expect(SearchArea.prefecture(named: "東京都") == "東京都")
        #expect(SearchArea.prefecture(named: "東京") == "東京都")
        #expect(SearchArea.prefecture(named: "京都") == "京都府")
        #expect(SearchArea.prefecture(named: " 大阪府 ") == "大阪府")
        #expect(SearchArea.prefecture(named: "北海道") == "北海道")
        #expect(SearchArea.prefecture(named: "京") == nil)
        #expect(SearchArea.prefecture(named: "Tokyo") == nil)
        #expect(SearchArea.prefecture(named: "") == nil)
        #expect(SearchArea.prefecture(named: nil) == nil)
    }

    /// 全国はすべての結果を残す
    @Test
    func nationwideKeepsEverything() {
        #expect(SearchArea.nationwide.keeps(Self.hit("大阪府")))
        #expect(SearchArea.nationwide.keeps(Self.hit(nil, latitude: 37.5, longitude: 127.0)))
    }

    /// 地方は、都道府県が分かれば地方の都道府県だけを残す（矩形に入る隣の地方の結果も取り除く）
    @Test
    func areaKeepsOnlyItsPrefectures() {
        #expect(SearchArea.kanto.keeps(Self.hit("東京都")))
        #expect(SearchArea.kanto.keeps(Self.hit("東京")))
        // 中部の矩形に入る埼玉県・群馬県の結果は、中部では取り除く
        #expect(!SearchArea.chubu.keeps(Self.hit("埼玉県", latitude: 36.0, longitude: 139.4)))
        #expect(!SearchArea.chubu.keeps(Self.hit("群馬県", latitude: 36.4, longitude: 139.0)))
        #expect(!SearchArea.kanto.keeps(Self.hit("大阪府", latitude: 34.69, longitude: 135.50)))
        #expect(SearchArea.kansai.keeps(Self.hit("大阪府", latitude: 34.69, longitude: 135.50)))
    }

    /// 都道府県が無い・知らない形のときは、座標が地方の矩形に入るかで決める
    @Test
    func areaFallsBackToBoundsWithoutPrefecture() {
        #expect(SearchArea.kanto.keeps(Self.hit(nil, latitude: 35.68, longitude: 139.77)))
        #expect(SearchArea.kanto.keeps(Self.hit("Tokyo", latitude: 35.68, longitude: 139.77)))
        #expect(!SearchArea.kanto.keeps(Self.hit(nil, latitude: 34.69, longitude: 135.50)))
        #expect(!SearchArea.kanto.keeps(Self.hit("Osaka", latitude: 34.69, longitude: 135.50)))
    }

    /// 初めのエリアは全国（06 の §4 の仮決め）
    @Test
    func initialAreaIsNationwide() {
        #expect(DomainConstants.SearchRegion.initialArea == .nationwide)
    }
}

/// S-08 で選んだ検索のエリアを端末に覚える（Issue #131）
struct SearchAreaStoreTests {
    /// テストだけで使う `UserDefaults`（ほかのテスト・アプリの値と混ぜない）
    static func makeDefaults() throws -> UserDefaults {
        let name = "SearchAreaStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// まだ選んでいなければ初めのエリア。覚えたエリアは、作り直した窓口からも読める（アプリを閉じても残る）
    @Test
    func remembersAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).area == DomainConstants.SearchRegion.initialArea)

        UserDefaultsSearchAreaStore(defaults: defaults).save(.kansai)
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).area == .kansai)
        #expect(defaults.string(forKey: UserDefaultsSearchAreaStore.key) == "kansai")
    }

    /// 覚えた値が知らないエリア（新しい版で消したエリアなど）なら、初めのエリアにする
    @Test
    func unknownValueFallsBackToInitialArea() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("tokai", forKey: UserDefaultsSearchAreaStore.key)
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).area == DomainConstants.SearchRegion.initialArea)
    }

    /// 擬似のサーバーの窓口は、メモリにだけ覚える（端末に残さない）
    @Test
    func inMemoryServicesDoNotUseUserDefaults() {
        let services = DataServices.inMemory(InMemoryServer.demo(.empty), scenario: .empty)
        #expect(services.searchArea is InMemorySearchAreaStore)
        services.searchArea.save(.okinawa)
        #expect(services.searchArea.area == .okinawa)
    }
}
