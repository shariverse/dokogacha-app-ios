//
//  PlaceCategoryTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import MapKit
import Testing

/// MapKit のカテゴリからアプリのカテゴリへの対応（02 の §3.1 の対応表）を確かめる。
struct PlaceCategoryTests {
    /// 02 の §3.1 の対応表の「主な MapKit カテゴリ」と、対応するアプリのカテゴリ
    nonisolated static let table: [(MKPointOfInterestCategory, PlaceCategory)] = [
        (.aquarium, .aquarium),
        (.park, .nature),
        (.nationalPark, .nature),
        (.campground, .nature),
        (.museum, .art),
        (.restaurant, .food),
        (.cafe, .food),
        (.bakery, .food),
        (.foodMarket, .food),
        (.brewery, .food),
        (.winery, .food),
        (.marina, .activity),
        (.stadium, .activity),
        (.fitnessCenter, .activity),
        (.amusementPark, .park),
        (.zoo, .park),
        (.store, .town),
        (.nightlife, .town),
        (.beach, .sea)
    ]

    /// 対応表の各行のとおりに決まる（場所名に寺社の語を含んでも MapKit のカテゴリを優先する）
    @Test(arguments: Self.table)
    func mapsPointOfInterestCategory(pointOfInterest: MKPointOfInterestCategory, expected: PlaceCategory) {
        #expect(PlaceCategory.mapped(from: pointOfInterest) == expected)
        #expect(PlaceCategory.classify(pointOfInterestCategory: pointOfInterest, placeName: "サンプル") == expected)
        #expect(PlaceCategory.classify(pointOfInterestCategory: pointOfInterest, placeName: "宮の森") == expected)
    }

    /// 対応表に無い MapKit のカテゴリは対応なし（nil）
    @Test
    func unmappedPointOfInterestCategory() {
        #expect(PlaceCategory.mapped(from: .airport) == nil)
        #expect(PlaceCategory.mapped(from: .publicTransport) == nil)
    }

    /// MapKit のカテゴリが無い・対応表に無いときは、場所名に「神社」「寺」「宮」を含めば寺社
    @Test(arguments: ["明治神宮", "浅草寺", "八坂神社", "太宰府天満宮"])
    func shrineByName(placeName: String) {
        #expect(PlaceCategory.classify(pointOfInterestCategory: nil, placeName: placeName) == .shrine)
        #expect(PlaceCategory.classify(pointOfInterestCategory: .hotel, placeName: placeName) == .shrine)
    }

    /// どれにも当てはまらないときは街歩き（02 の §3.1「対応しきれない場合は town にする」）
    @Test
    func fallsBackToTown() {
        #expect(PlaceCategory.fallback == .town)
        #expect(PlaceCategory.classify(pointOfInterestCategory: nil, placeName: "渋谷スクランブル交差点") == .town)
        #expect(PlaceCategory.classify(pointOfInterestCategory: .airport, placeName: "羽田空港") == .town)
    }

    /// 保存する値は 9 種で、05 の §3・tokens.json の鍵と同じ（tokens.json との突き合わせは `DesignTokensTests`）
    @Test
    func rawValuesAreTheNineCategories() {
        #expect(PlaceCategory.allCases.map(\.rawValue) == [
            "aquarium", "nature", "art", "food", "activity", "park", "town", "shrine", "sea"
        ])
    }
}
