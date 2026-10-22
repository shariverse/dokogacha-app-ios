//
//  MapOpener.swift
//  Dokogacha
//

import CoreLocation
import MapKit

/// 場所を地図のアプリで開く窓口（03 の S-10・S-14「マップで開く」）。
///
/// MapKit（`MKMapItem.openInMaps`）を画面の Model から切り離し、Unit テストでは呼び出しを記録するものに差し替える
/// （Simulator のテストからマップのアプリを開くと、テストのアプリが裏に回る）。
protocol MapOpener {
    /// 場所（座標と名前）を地図のアプリで開く
    func open(_ place: Place)
}

/// Apple のマップで開く（`MKMapItem.openInMaps`。05 の §1）。
///
/// 座標と場所名だけで開く（`mapItemId` から場所を引き直さない。iOS 17 で使えず、通信も要るため）。
/// 位置情報の許可は要らない（自分の現在地を使わない）
struct AppleMapsOpener: MapOpener {
    func open(_ place: Place) {
        Self.mapItem(for: place).openInMaps()
    }

    /// 場所の座標と名前を持つ `MKMapItem`
    static func mapItem(for place: Place) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let item: MKMapItem
        if #available(iOS 26, *) {
            // iOS 26 で `MKPlacemark` が非推奨になり、座標だけから作る初期化が足された
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = place.name
        return item
    }
}
