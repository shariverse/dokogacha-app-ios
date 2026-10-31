//
//  PlaceSearchService.swift
//  Dokogacha
//

import MapKit

/// 場所検索（F-10「MapKit の場所検索（`MKLocalSearch`）を使って場所を選ぶ」）の窓口。画面の Model はこの protocol だけを見る。
///
/// 実装は MapKit（`MapKitPlaceSearchService`）と、Unit テスト・`-uiTesting`・撮影モード・プレビューの擬似の検索（`DemoPlaceSearchService`）。
/// 位置情報は使わない（02 の §9）。範囲は S-08 で選んだエリア（`SearchScope`。全国・地方・都道府県・市区町村）。
protocol PlaceSearchService {
    /// 語で場所を探す。見つからなければ空の配列。通信できないときは `AppError` を投げる
    /// - Parameters:
    ///   - query: 検索する語（前後の空白を取り除いたもの。空では呼ばない）
    ///   - scope: 探すエリア（全国・地方・都道府県・市区町村）
    func search(_ query: String, in scope: SearchScope) async throws -> [SearchedPlace]
}

/// `MKLocalSearch` で場所を探す実装。
///
/// - 範囲は選んだエリアを囲む矩形（06 の §4 の仮決め。`DomainConstants.SearchRegion`・`Prefecture.all`）。iOS 18 以降は矩形の外の結果を出さない
///   （`regionPriority = .required`）。全国の矩形は日本の外（韓国などの一部）も含むので、日本の場所だけになるとは限らない
/// - 市区町村は、住所の検索（「東京都豊島区」）で市区町村の範囲を引いて、その範囲で探す（引いた範囲は起動している間だけ覚える）。
///   引けなければ都道府県の矩形で探す
/// - 地方・都道府県・市区町村のときは、範囲に入る隣の結果を都道府県・市区町村の名前で取り除く
///   （`SearchScope.keeps`。MapKit の結果は最大 25 件なので、それより少なくなる）
/// - 結果の種類は施設（`pointOfInterest`）。iOS 18 以降は山・湖などの地形（`physicalFeature`）も含める（「高尾山」などを探せるように）
/// - 位置情報の許可は取らない（`MKLocalSearch` は許可が無くても範囲を指定して検索できる）
struct MapKitPlaceSearchService: PlaceSearchService {
    /// 引いた市区町村の範囲（団体コードごと）。同じ市区町村で探し直すたびに引き直さない
    private let municipalityBounds = MunicipalityBoundsCache()

    /// 矩形の検索の範囲
    /// - Parameter bounds: 探す矩形
    static func region(for bounds: SearchBounds) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLatitude, longitude: bounds.centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: bounds.latitudeDelta, longitudeDelta: bounds.longitudeDelta)
        )
    }

    func search(_ query: String, in scope: SearchScope) async throws -> [SearchedPlace] {
        let bounds = try await searchBounds(for: scope)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = Self.region(for: bounds)
        if #available(iOS 18.0, *) {
            request.resultTypes = [.pointOfInterest, .physicalFeature]
            request.regionPriority = .required
        } else {
            request.resultTypes = .pointOfInterest
        }
        let response = try await Self.start(request)
        return (response?.mapItems ?? [])
            .map(Self.hit)
            .filter { scope.keeps($0, searchedIn: bounds) }
            .compactMap(SearchedPlace.make)
    }

    /// 探す範囲。市区町村は、覚えている範囲か、住所の検索で引いた範囲（引けなければ都道府県の矩形）
    private func searchBounds(for scope: SearchScope) async throws -> SearchBounds {
        guard let municipality = scope.municipality, let prefecture = scope.prefecture else {
            return scope.bounds
        }
        if let bounds = municipalityBounds.bounds(of: municipality) {
            return bounds
        }
        let bounds = try await Self.lookUpBounds(of: municipality, in: prefecture) ?? prefecture.bounds
        municipalityBounds.store(bounds, of: municipality)
        return bounds
    }

    /// 住所の検索（「東京都豊島区」）で、市区町村の範囲を引く。
    ///
    /// 都道府県の矩形を範囲にして探すが、矩形の外の島の町村（八丈町など）も引けるよう、範囲の外を出さない指定はしない。
    /// 引いた場所が別の都道府県・市区町村なら使わない（名前が日本語でなく突き合わせられないときは使う）。狭すぎる範囲は広げる
    /// - Returns: 市区町村の範囲。見つからなければ nil
    private static func lookUpBounds(of municipality: Municipality, in prefecture: Prefecture) async throws -> SearchBounds? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = prefecture.name + municipality.name
        request.resultTypes = .address
        request.region = region(for: prefecture.bounds)
        guard let response = try await start(request), let item = response.mapItems.first else {
            return nil
        }
        let found = hit(item)
        guard
            Prefecture.named(found.administrativeArea).map({ $0 == prefecture }) ?? true,
            PlaceLocality.matches(locality: found.locality, subLocality: found.subLocality, municipality: municipality.name) ?? true
        else {
            return nil
        }
        let region = response.boundingRegion
        return SearchBounds(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta,
            minimumDelta: DomainConstants.SearchRegion.minimumMunicipalityDelta
        )
    }

    /// 検索する。見つからないときは nil（失敗ではなく、結果 0 件）。止めたとき・通信できないときは `AppError` を投げる
    private static func start(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response? {
        do {
            return try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return nil
        } catch {
            throw Task.isCancelled ? AppError(.cancelled, code: .cancelled) : AppError(.network)
        }
    }

    /// MapKit の結果 1 件を、アプリの検索結果にする（投稿できない結果は nil）。
    ///
    /// 写し方を Unit テストで確かめるため、外から呼べるようにしてある（`SearchedPlaceTests`）
    static func searchedPlace(_ item: MKMapItem) -> SearchedPlace? {
        SearchedPlace.make(hit(item))
    }

    /// MapKit の結果 1 件の、名前・都道府県・市区町村・座標・識別子（iOS 18 以降）・カテゴリを `PlaceSearchHit` に写す
    static func hit(_ item: MKMapItem) -> PlaceSearchHit {
        let placemark = item.placemark
        var mapItemID: String?
        if #available(iOS 18.0, *) {
            mapItemID = item.identifier?.rawValue
        }
        return PlaceSearchHit(
            name: item.name,
            administrativeArea: placemark.administrativeArea,
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            mapItemID: mapItemID,
            pointOfInterestCategory: item.pointOfInterestCategory
        )
    }
}

/// MapKit で引いた市区町村の範囲を、起動している間だけ覚える（団体コードごと）
final class MunicipalityBoundsCache {
    private var boundsByCode: [String: SearchBounds] = [:]

    /// 覚えている範囲。まだ引いていなければ nil
    func bounds(of municipality: Municipality) -> SearchBounds? {
        boundsByCode[municipality.code]
    }

    /// 引いた範囲を覚える
    func store(_ bounds: SearchBounds, of municipality: Municipality) {
        boundsByCode[municipality.code] = bounds
    }
}
