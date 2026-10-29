//
//  PlaceSearchService.swift
//  Dokogacha
//

import MapKit

/// 場所検索（F-10「MapKit の場所検索（`MKLocalSearch`）を使って場所を選ぶ」）の窓口。画面の Model はこの protocol だけを見る。
///
/// 実装は MapKit（`MapKitPlaceSearchService`）と、Unit テスト・`-uiTesting`・撮影モード・プレビューの擬似の検索（`DemoPlaceSearchService`）。
/// 位置情報は使わない（02 の §9）。範囲は S-08 で選んだエリア（`SearchArea`。矩形は `DomainConstants.SearchRegion`）。
protocol PlaceSearchService {
    /// 語で場所を探す。見つからなければ空の配列。通信できないときは `AppError` を投げる
    /// - Parameters:
    ///   - query: 検索する語（前後の空白を取り除いたもの。空では呼ばない）
    ///   - area: 探すエリア（全国か地方）
    func search(_ query: String, in area: SearchArea) async throws -> [SearchedPlace]
}

/// `MKLocalSearch` で場所を探す実装。
///
/// - 範囲は選んだエリアを囲む矩形（06 の §4 の仮決め。`DomainConstants.SearchRegion`）。iOS 18 以降は矩形の外の結果を出さない
///   （`regionPriority = .required`）。全国の矩形は日本の外（韓国などの一部）も含むので、日本の場所だけになるとは限らない
/// - 地方のときは、矩形に入る隣の地方の結果を都道府県で取り除く（`SearchArea.keeps`。MapKit の結果は最大 25 件なので、それより少なくなる）
/// - 結果の種類は施設（`pointOfInterest`）。iOS 18 以降は山・湖などの地形（`physicalFeature`）も含める（「高尾山」などを探せるように）
/// - 位置情報の許可は取らない（`MKLocalSearch` は許可が無くても範囲を指定して検索できる）
struct MapKitPlaceSearchService: PlaceSearchService {
    /// エリアの検索の範囲
    /// - Parameter area: 探すエリア
    static func region(for area: SearchArea) -> MKCoordinateRegion {
        let bounds = area.bounds
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLatitude, longitude: bounds.centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: bounds.latitudeDelta, longitudeDelta: bounds.longitudeDelta)
        )
    }

    func search(_ query: String, in area: SearchArea) async throws -> [SearchedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = Self.region(for: area)
        if #available(iOS 18.0, *) {
            request.resultTypes = [.pointOfInterest, .physicalFeature]
            request.regionPriority = .required
        } else {
            request.resultTypes = .pointOfInterest
        }
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            // 見つからないときは失敗ではなく、結果 0 件（「見つかりませんでした」）
            return []
        } catch {
            throw Task.isCancelled ? AppError(.cancelled, code: .cancelled) : AppError(.network)
        }
        return response.mapItems
            .map(Self.hit)
            .filter { area.keeps($0) }
            .compactMap(SearchedPlace.make)
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
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude,
            mapItemID: mapItemID,
            pointOfInterestCategory: item.pointOfInterestCategory
        )
    }
}
