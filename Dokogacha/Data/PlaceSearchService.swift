//
//  PlaceSearchService.swift
//  Dokogacha
//

import MapKit

/// 場所検索（F-10「MapKit の場所検索（`MKLocalSearch`）を使って場所を選ぶ」）の窓口。画面の Model はこの protocol だけを見る。
///
/// 実装は MapKit（`MapKitPlaceSearchService`）と、Unit テスト・`-uiTesting`・撮影モード・プレビューの擬似の検索（`DemoPlaceSearchService`）。
/// 位置情報は使わない（02 の §9「場所検索は地域を指定しない全国検索」。範囲は `DomainConstants.SearchRegion`）。
protocol PlaceSearchService {
    /// 語で場所を探す。見つからなければ空の配列。通信できないときは `AppError` を投げる
    /// - Parameter query: 検索する語（前後の空白を取り除いたもの。空では呼ばない）
    func search(_ query: String) async throws -> [SearchedPlace]
}

/// `MKLocalSearch` で場所を探す実装。
///
/// - 範囲は日本全体（06 の §4 の仮決め。`DomainConstants.SearchRegion`）。iOS 18 以降は範囲の外の結果を出さない（`regionPriority = .required`）
/// - 結果の種類は施設（`pointOfInterest`）。iOS 18 以降は山・湖などの地形（`physicalFeature`）も含める（「高尾山」などを探せるように）
/// - 位置情報の許可は取らない（`MKLocalSearch` は許可が無くても範囲を指定して検索できる）
struct MapKitPlaceSearchService: PlaceSearchService {
    /// 検索の範囲（日本全体）
    static var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: DomainConstants.SearchRegion.centerLatitude,
                longitude: DomainConstants.SearchRegion.centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: DomainConstants.SearchRegion.latitudeDelta,
                longitudeDelta: DomainConstants.SearchRegion.longitudeDelta
            )
        )
    }

    func search(_ query: String) async throws -> [SearchedPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = Self.region
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
        return response.mapItems.compactMap(Self.searchedPlace)
    }

    /// MapKit の結果 1 件を、アプリの検索結果にする（投稿できない結果は nil）
    private static func searchedPlace(_ item: MKMapItem) -> SearchedPlace? {
        let placemark = item.placemark
        var mapItemID: String?
        if #available(iOS 18.0, *) {
            mapItemID = item.identifier?.rawValue
        }
        return SearchedPlace.make(
            PlaceSearchHit(
                name: item.name,
                administrativeArea: placemark.administrativeArea,
                locality: placemark.locality,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                mapItemID: mapItemID,
                pointOfInterestCategory: item.pointOfInterestCategory
            )
        )
    }
}
