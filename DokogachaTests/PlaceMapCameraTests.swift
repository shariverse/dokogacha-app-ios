//
//  PlaceMapCameraTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import MapKit
import Testing

/// S-17 場所の地図の、最初に映す範囲とカードの文言を確かめる。
struct PlaceMapCameraTests {
    /// 最初の範囲はピン（場所）を中心にし、上下・左右に `initialSpanMeters` を映す
    @Test
    func initialRegionCentersOnPlace() {
        let place = Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil)
        let region = PlaceMapCamera.initialRegion(for: place)
        #expect(region.center.latitude == place.latitude)
        #expect(region.center.longitude == place.longitude)
        // 緯度 1 度は約 111km。1,200m 四方なら 0.0108 度前後
        let expectedDelta = PlaceMapCamera.initialSpanMeters / 111_000
        #expect(abs(region.span.latitudeDelta - expectedDelta) < 0.001)
        #expect(region.span.longitudeDelta > region.span.latitudeDelta)
    }

    /// 何度求めても同じ範囲になる（「元の位置に戻す」で最初の範囲に戻る）
    @Test
    func initialRegionIsStable() {
        let place = Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.2994, longitude: 139.4800, mapItemId: nil)
        let first = PlaceMapCamera.initialRegion(for: place)
        let second = PlaceMapCamera.initialRegion(for: place)
        #expect(first.center.latitude == second.center.latitude)
        #expect(first.center.longitude == second.center.longitude)
        #expect(first.span.latitudeDelta == second.span.latitudeDelta)
        #expect(first.span.longitudeDelta == second.span.longitudeDelta)
    }

    /// カードの 2 行目は「エリア · カテゴリ」。エリアが空ならカテゴリだけ
    @Test(arguments: [
        ("東京・豊島区", "水族館", "東京・豊島区 · 水族館"),
        ("", "水族館", "水族館")
    ])
    func meta(area: String, label: String, expected: String) {
        #expect(PlaceMapCamera.meta(area: area, categoryLabel: label) == expected)
    }
}
