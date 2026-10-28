//
//  SearchedPlaceTests.swift
//  DokogachaTests
//

import Contacts
@testable import Dokogacha
import Foundation
import MapKit
import Testing

/// 場所検索の結果を、エリアの表示（「東京・豊島区」）・カテゴリ（02 の §3.1 の対応表と場所名）付きの場所にすることを確かめる
struct SearchedPlaceTests {
    /// 東京駅の近くの座標
    static let latitude = 35.681_2
    static let longitude = 139.767_1

    static func hit(
        name: String? = "東京駅",
        prefecture: String? = "東京都",
        city: String? = "千代田区",
        mapItemID: String? = nil,
        category: MKPointOfInterestCategory? = nil
    ) -> PlaceSearchHit {
        PlaceSearchHit(
            name: name,
            administrativeArea: prefecture,
            locality: city,
            latitude: latitude,
            longitude: longitude,
            mapItemID: mapItemID,
            pointOfInterestCategory: category
        )
    }

    // MARK: - エリア

    /// 都道府県の末尾の「都」「府」「県」を外し、市区町村と「・」でつなぐ（02 の §3.1「東京・豊島区」）
    @Test(arguments: [
        ("東京都", "豊島区", "東京・豊島区"),
        ("神奈川県", "横浜市", "神奈川・横浜市"),
        ("大阪府", "大阪市", "大阪・大阪市"),
        ("京都府", "京都市", "京都・京都市"),
        ("北海道", "札幌市", "北海道・札幌市")
    ])
    func areaJoinsPrefectureAndCity(_ prefecture: String, _ city: String, _ expected: String) {
        #expect(PlaceArea.text(administrativeArea: prefecture, locality: city) == expected)
    }

    /// 片方しか無ければその片方だけ、どちらも無ければ空。外すと 1 文字になる名前は外さない。同じ名前は 1 つにする
    @Test
    func areaWithMissingOrSameParts() {
        #expect(PlaceArea.text(administrativeArea: "大阪府", locality: nil) == "大阪")
        #expect(PlaceArea.text(administrativeArea: nil, locality: "鎌倉市") == "鎌倉市")
        #expect(PlaceArea.text(administrativeArea: nil, locality: nil).isEmpty)
        #expect(PlaceArea.text(administrativeArea: " ", locality: "").isEmpty)
        #expect(PlaceArea.text(administrativeArea: "京都", locality: nil) == "京都")
        #expect(PlaceArea.text(administrativeArea: "東京都", locality: "東京都") == "東京")
    }

    /// エリアが 50 文字を超えたら都道府県だけにし、それでも長ければ空にする（場所は捨てない）
    @Test
    func tooLongAreaFallsBack() throws {
        let longCity = String(repeating: "あ", count: DomainConstants.Limits.placeAreaLength.upperBound)
        let prefectureOnly = try #require(SearchedPlace.make(Self.hit(city: longCity)))
        #expect(prefectureOnly.place.area == "東京")
        let longPrefecture = String(repeating: "い", count: 60)
        let empty = try #require(SearchedPlace.make(Self.hit(prefecture: longPrefecture, city: longCity)))
        #expect(empty.place.area.isEmpty)
    }

    // MARK: - カテゴリ

    /// MapKit のカテゴリを対応表で引き、無ければ場所名（「神社」「寺」「宮」）、それも無ければ街歩き（02 の §3.1）
    @Test
    func classifiesByMapKitCategoryThenName() throws {
        #expect(try #require(SearchedPlace.make(Self.hit(name: "すみだ水族館", category: .aquarium))).category == .aquarium)
        #expect(try #require(SearchedPlace.make(Self.hit(name: "上野公園", category: .park))).category == .nature)
        #expect(try #require(SearchedPlace.make(Self.hit(name: "築地場外市場", category: .foodMarket))).category == .food)
        #expect(try #require(SearchedPlace.make(Self.hit(name: "明治神宮"))).category == .shrine)
        #expect(try #require(SearchedPlace.make(Self.hit(name: "浅草寺"))).category == .shrine)
        // MapKit のカテゴリがあれば、名前に「宮」があっても寺社にしない
        #expect(try #require(SearchedPlace.make(Self.hit(name: "宮城県美術館", category: .museum))).category == .art)
        // 対応表に無いカテゴリ・カテゴリ無しは街歩き
        #expect(try #require(SearchedPlace.make(Self.hit(name: "東京駅", category: .publicTransport))).category == .town)
        #expect(try #require(SearchedPlace.make(Self.hit(name: "東京駅"))).category == .town)
    }

    // MARK: - 場所と ID

    /// 場所は前後の空白を取り除いた名前と座標で作り、ID は MapKit の識別子（無ければ名前と座標）
    @Test
    func buildsPlaceAndIdentifier() throws {
        let withID = try #require(SearchedPlace.make(Self.hit(name: "  東京駅 ", mapItemID: "I1234")))
        #expect(withID.place == Place(name: "東京駅", area: "東京・千代田区", latitude: Self.latitude, longitude: Self.longitude, mapItemId: "I1234"))
        #expect(withID.id == "I1234")
        let withoutID = try #require(SearchedPlace.make(Self.hit()))
        #expect(withoutID.place.mapItemId == nil)
        #expect(withoutID.id == "東京駅@\(Self.latitude),\(Self.longitude)")
    }

    /// 保存できない識別子（前後に空白・長すぎる）は持たない。名前が無い・空・長すぎる結果は出さない
    @Test
    func dropsUnacceptableValues() throws {
        let spaced = try #require(SearchedPlace.make(Self.hit(mapItemID: " I1234")))
        #expect(spaced.place.mapItemId == nil)
        let long = String(repeating: "a", count: DomainConstants.Limits.mapItemIDMaxLength + 1)
        #expect(try #require(SearchedPlace.make(Self.hit(mapItemID: long))).place.mapItemId == nil)
        #expect(SearchedPlace.make(Self.hit(name: nil)) == nil)
        #expect(SearchedPlace.make(Self.hit(name: "  ")) == nil)
        let tooLong = String(repeating: "あ", count: DomainConstants.Limits.placeNameLength.upperBound + 1)
        #expect(SearchedPlace.make(Self.hit(name: tooLong)) == nil)
    }

    /// 同じ ID の結果は先の 1 件だけを残し、並びは保つ（MapKit が同じ場所を 2 件返しても、行の ID が重ならない）
    @Test
    func uniquedDropsRepeatedIDs() throws {
        let station = try #require(SearchedPlace.make(Self.hit(mapItemID: "I1")))
        let same = try #require(SearchedPlace.make(Self.hit(name: "東京駅 丸の内口", mapItemID: "I1")))
        let other = try #require(SearchedPlace.make(Self.hit(name: "皇居")))
        let unnamedTwin = try #require(SearchedPlace.make(Self.hit(name: "皇居")))

        let result = SearchedPlace.uniqued([station, other, same, unnamedTwin])

        #expect(result.map(\.id) == ["I1", other.id])
        #expect(result.first?.place.name == "東京駅")
        #expect(SearchedPlace.uniqued([]).isEmpty)
    }

    // MARK: - 擬似の検索

    /// 擬似の検索は、名前・エリア・語に当たる場所を一覧の順に返し、同じ判定でカテゴリを付ける。空の語では何も返さない
    @Test
    func demoSearchReturnsFixedResults() {
        let aquariums = DemoPlaceSearchService.results(for: "水族館")
        #expect(aquariums.map(\.place.name) == ["すみだ水族館", "サンシャイン水族館", "しながわ水族館", "鴨川シーワールド"])
        #expect(aquariums.allSatisfy { $0.category == .aquarium })
        #expect(aquariums.first?.id == DemoPlaceSearchService.sumidaAquariumID)
        #expect(aquariums.first?.place.area == "東京・墨田区")
        #expect(DemoPlaceSearchService.results(for: "明治神宮").map(\.category) == [.shrine])
        #expect(DemoPlaceSearchService.results(for: "海").map(\.place.name) == ["鴨川シーワールド", "江の島", "由比ヶ浜海水浴場"])
        #expect(DemoPlaceSearchService.results(for: " ").isEmpty)
        #expect(DemoPlaceSearchService.results(for: "存在しない場所").isEmpty)
    }

    // MARK: - MapKit の結果の写し

    /// MapKit の結果（`MKMapItem`）の名前・住所・座標・カテゴリを写して、検索結果にする
    @Test
    func convertsMapItem() throws {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 35.710_1, longitude: 139.810_7),
            addressDictionary: [CNPostalAddressStateKey: "東京都", CNPostalAddressCityKey: "墨田区"]
        )
        let item = MKMapItem(placemark: placemark)
        item.name = "すみだ水族館"
        item.pointOfInterestCategory = .aquarium

        let place = try #require(MapKitPlaceSearchService.searchedPlace(item))

        #expect(place.place.name == "すみだ水族館")
        #expect(place.place.area == "東京・墨田区")
        #expect(place.place.latitude == 35.710_1)
        #expect(place.place.longitude == 139.810_7)
        #expect(place.category == .aquarium)
        // 手で作った `MKMapItem` には識別子が無いので、場所名と座標から ID を作る
        #expect(place.place.mapItemId == nil)
        #expect(place.id == "すみだ水族館@35.7101,139.8107")
    }

    /// 住所もカテゴリも無い MapKit の結果は、エリアを空・カテゴリを街歩きにする
    /// （名前が無い `MKMapItem` は `name` が「場所: 不明」を返すので、名前が無い場合は `PlaceSearchHit` の段で確かめる）
    @Test
    func convertsMapItemWithoutDetails() throws {
        let bare = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0)))
        bare.name = "名もない広場"
        let place = try #require(MapKitPlaceSearchService.searchedPlace(bare))
        #expect(place.place.area.isEmpty)
        #expect(place.category == .town)
    }

    /// MapKit の検索の範囲は、エリアの矩形（`DomainConstants.SearchRegion`）の中心と幅
    @Test(arguments: SearchArea.allCases)
    func mapKitRegionMatchesArea(area: SearchArea) {
        let region = MapKitPlaceSearchService.region(for: area)
        #expect(region.center.latitude == area.bounds.centerLatitude)
        #expect(region.center.longitude == area.bounds.centerLongitude)
        #expect(region.span.latitudeDelta == area.bounds.latitudeDelta)
        #expect(region.span.longitudeDelta == area.bounds.longitudeDelta)
    }
}
