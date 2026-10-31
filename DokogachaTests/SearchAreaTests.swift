//
//  SearchAreaTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の検索のエリアの地方（`SearchArea`）を確かめる: 地方の矩形に主な都市が入る・都道府県の分け方（Issue #131・#160）
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

    /// 地方の都道府県は、47 の都道府県を重ならずに 1 回ずつ持つ（#131 の地方の分け方のまま）。全国は都道府県で絞らない
    @Test
    func prefecturesCoverJapanOnce() {
        let prefectures = SearchArea.allCases.flatMap(\.prefectures)
        #expect(prefectures.count == 47)
        #expect(Set(prefectures.map(\.code)).count == 47)
        #expect(SearchArea.nationwide.prefectures.isEmpty)
        #expect(SearchArea.allCases.filter { $0 != .nationwide }.allSatisfy { !$0.prefectures.isEmpty })
        #expect(SearchArea.kanto.prefectures.map(\.name) == ["茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県"])
        #expect(SearchArea.chugokuShikoku.prefectures.map(\.name) == [
            "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県"
        ])
    }

    /// 都道府県が 1 つだけの地方（北海道・沖縄）は、地方を選べば都道府県も決まる
    @Test
    func soloPrefectureOnlyForHokkaidoAndOkinawa() {
        #expect(SearchArea.hokkaido.soloPrefecture?.name == "北海道")
        #expect(SearchArea.okinawa.soloPrefecture?.name == "沖縄県")
        #expect(SearchArea.allCases.filter { $0.soloPrefecture != nil } == [.hokkaido, .okinawa])
    }

    /// 初めのエリアは全国（06 の §4 の仮決め）
    @Test
    func initialScopeIsNationwide() {
        #expect(DomainConstants.SearchRegion.initialScope == .nationwide)
    }
}

/// S-08 で選んだ検索のエリアを端末に覚える（Issue #131・#160）
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
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == DomainConstants.SearchRegion.initialScope)

        UserDefaultsSearchAreaStore(defaults: defaults).save(SearchScope(area: .kansai))
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == SearchScope(area: .kansai))
        #expect(defaults.string(forKey: UserDefaultsSearchAreaStore.key) == "kansai")
        #expect(defaults.object(forKey: UserDefaultsSearchAreaStore.prefectureKey) == nil)
    }

    /// 都道府県・市区町村まで覚え、一段上に戻したら下の段は忘れる
    @Test
    func remembersPrefectureAndMunicipality() throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsSearchAreaStore(defaults: defaults)
        let sumida = try #require(MunicipalityCatalog.bundled.municipality(code: "131075"))
        let sumidaScope = try #require(SearchScope(municipality: sumida))

        store.save(sumidaScope)
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == sumidaScope)
        #expect(defaults.string(forKey: UserDefaultsSearchAreaStore.key) == "kanto")
        #expect(defaults.integer(forKey: UserDefaultsSearchAreaStore.prefectureKey) == 13)
        #expect(defaults.string(forKey: UserDefaultsSearchAreaStore.municipalityKey) == "131075")

        let tokyo = try #require(Prefecture.code(13))
        store.save(SearchScope(prefecture: tokyo))
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == SearchScope(prefecture: tokyo))
        #expect(defaults.object(forKey: UserDefaultsSearchAreaStore.municipalityKey) == nil)
    }

    /// #131 の版で地方だけを覚えた端末は、同じ地方全体を選んだ状態で開く
    @Test(arguments: SearchArea.allCases)
    func migratesAreaOnlyValue(area: SearchArea) throws {
        let defaults = try Self.makeDefaults()
        defaults.set(area.rawValue, forKey: UserDefaultsSearchAreaStore.key)
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == SearchScope(area: area))
    }

    /// 覚えた値が知らないエリア（新しい版で消したエリアなど）なら、初めのエリアにする
    @Test
    func unknownValueFallsBackToInitialScope() throws {
        let defaults = try Self.makeDefaults()
        defaults.set("tokai", forKey: UserDefaultsSearchAreaStore.key)
        defaults.set(13, forKey: UserDefaultsSearchAreaStore.prefectureKey)
        #expect(UserDefaultsSearchAreaStore(defaults: defaults).scope == DomainConstants.SearchRegion.initialScope)
    }

    /// 擬似のサーバーの窓口は、メモリにだけ覚える（端末に残さない）
    @Test
    func inMemoryServicesDoNotUseUserDefaults() {
        let services = DataServices.inMemory(InMemoryServer.demo(.empty), scenario: .empty)
        #expect(services.searchArea is InMemorySearchAreaStore)
        services.searchArea.save(SearchScope(area: .okinawa))
        #expect(services.searchArea.scope == SearchScope(area: .okinawa))
    }
}
