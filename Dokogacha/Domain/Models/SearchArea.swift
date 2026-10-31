//
//  SearchArea.swift
//  Dokogacha
//

import Foundation

/// S-08「場所を探す」で選ぶ、検索するエリアの地方（全国か地方。03 の S-08 の 6）。
///
/// 位置情報を使わずに検索の範囲を決めるため、利用者が選ぶ（02 の §9）。`MKLocalSearch` は範囲の中心に近い場所を上位に返すので、
/// 日本全体の範囲だけでは、一般的な語（「グルメ」など）の結果が範囲の中心（兵庫県のあたり）の近くに偏る（Issue #131）。
///
/// 地方は 8 地方区分のうち、中国と四国をまとめ、九州と沖縄を分けたもの。地方を囲む矩形（`bounds`）を検索の範囲にし、
/// 矩形に入ってしまう隣の地方の結果は、都道府県で取り除く（`SearchScope.keeps`）。
/// 地方の次に都道府県・市区町村まで選べる（`SearchScope`。Issue #160）。rawValue は端末に覚えるので変えない（`SearchAreaStore`）
nonisolated enum SearchArea: String, CaseIterable, Identifiable, Sendable {
    /// 全国
    case nationwide
    /// 北海道
    case hokkaido
    /// 東北
    case tohoku
    /// 関東
    case kanto
    /// 中部
    case chubu
    /// 関西（近畿）
    case kansai
    /// 中国・四国
    case chugokuShikoku
    /// 九州
    case kyushu
    /// 沖縄
    case okinawa

    var id: String {
        rawValue
    }

    /// 検索の範囲（`MKLocalSearch` の `region` にする矩形。`DomainConstants.SearchRegion`）
    var bounds: SearchBounds {
        switch self {
        case .nationwide: DomainConstants.SearchRegion.nationwide
        case .hokkaido: DomainConstants.SearchRegion.hokkaido
        case .tohoku: DomainConstants.SearchRegion.tohoku
        case .kanto: DomainConstants.SearchRegion.kanto
        case .chubu: DomainConstants.SearchRegion.chubu
        case .kansai: DomainConstants.SearchRegion.kansai
        case .chugokuShikoku: DomainConstants.SearchRegion.chugokuShikoku
        case .kyushu: DomainConstants.SearchRegion.kyushu
        case .okinawa: DomainConstants.SearchRegion.okinawa
        }
    }

    /// 地方に入る都道府県（都道府県コードの順）。全国は空（都道府県で絞らない）
    var prefectures: [Prefecture] {
        Prefecture.all.filter { $0.area == self }
    }

    /// 地方に都道府県が 1 つだけのとき（北海道・沖縄）の、その都道府県。地方を選べば都道府県も選んだことになる
    var soloPrefecture: Prefecture? {
        let prefectures = prefectures
        return prefectures.count == 1 ? prefectures.first : nil
    }
}

/// 緯度・経度の矩形（検索の範囲。北緯・東経の度）
nonisolated struct SearchBounds: Equatable, Hashable, Sendable {
    /// 南の端の緯度
    let minLatitude: Double
    /// 北の端の緯度
    let maxLatitude: Double
    /// 西の端の経度
    let minLongitude: Double
    /// 東の端の経度
    let maxLongitude: Double

    init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// 南北・西東の範囲から作る（都道府県の表を短く書くため）
    init(latitude: ClosedRange<Double>, longitude: ClosedRange<Double>) {
        self.init(
            minLatitude: latitude.lowerBound,
            maxLatitude: latitude.upperBound,
            minLongitude: longitude.lowerBound,
            maxLongitude: longitude.upperBound
        )
    }

    /// 中心と幅から作る（MapKit の範囲を写すため）。幅が `minimumDelta` より狭ければ、中心を変えずに広げる
    init(centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double, minimumDelta: Double = 0) {
        let latitudeHalf = max(latitudeDelta, minimumDelta) / 2
        let longitudeHalf = max(longitudeDelta, minimumDelta) / 2
        self.init(
            minLatitude: centerLatitude - latitudeHalf,
            maxLatitude: centerLatitude + latitudeHalf,
            minLongitude: centerLongitude - longitudeHalf,
            maxLongitude: centerLongitude + longitudeHalf
        )
    }

    /// 中心の緯度
    var centerLatitude: Double {
        (minLatitude + maxLatitude) / 2
    }

    /// 中心の経度
    var centerLongitude: Double {
        (minLongitude + maxLongitude) / 2
    }

    /// 緯度の幅（度）
    var latitudeDelta: Double {
        maxLatitude - minLatitude
    }

    /// 経度の幅（度）
    var longitudeDelta: Double {
        maxLongitude - minLongitude
    }

    /// 座標が矩形に入るか（端を含む）
    func contains(latitude: Double, longitude: Double) -> Bool {
        (minLatitude...maxLatitude).contains(latitude) && (minLongitude...maxLongitude).contains(longitude)
    }
}
