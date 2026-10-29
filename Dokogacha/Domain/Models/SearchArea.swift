//
//  SearchArea.swift
//  Dokogacha
//

import Foundation

/// S-08「場所を探す」で選ぶ、検索するエリア（全国か地方。03 の S-08 の 6）。
///
/// 位置情報を使わずに検索の範囲を決めるため、利用者が選ぶ（02 の §9）。`MKLocalSearch` は範囲の中心に近い場所を上位に返すので、
/// 日本全体の範囲だけでは、一般的な語（「グルメ」など）の結果が範囲の中心（兵庫県のあたり）の近くに偏る（Issue #131）。
///
/// 地方は 8 地方区分のうち、中国と四国をまとめ、九州と沖縄を分けたもの。地方を囲む矩形（`bounds`）を検索の範囲にし、
/// 矩形に入ってしまう隣の地方の結果は、都道府県で取り除く（`keeps(_:)`）
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

    /// 地方に入る都道府県（`MKPlacemark.administrativeArea` の「東京都」の形）。全国は nil（都道府県で絞らない）
    var prefectures: [String]? {
        switch self {
        case .nationwide:
            nil
        case .hokkaido:
            ["北海道"]
        case .tohoku:
            ["青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県"]
        case .kanto:
            ["茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県"]
        case .chubu:
            ["新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県", "静岡県", "愛知県"]
        case .kansai:
            ["三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県"]
        case .chugokuShikoku:
            ["鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県"]
        case .kyushu:
            ["福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県"]
        case .okinawa:
            ["沖縄県"]
        }
    }

    /// 地方に分けた 47 の都道府県
    static var allPrefectures: [String] {
        allCases.flatMap { $0.prefectures ?? [] }
    }

    /// 検索の結果を、このエリアの結果として残すか。
    ///
    /// - 全国: すべて残す（範囲の矩形だけで絞る）
    /// - 地方: 都道府県が分かれば、地方の都道府県のときだけ残す。都道府県が無い・知らない形（英語の名前など）なら、
    ///   座標が範囲の矩形に入るときだけ残す（iOS 17 では矩形の外の結果も届くため）
    /// - Parameter hit: MapKit の検索結果から取り出した値
    func keeps(_ hit: PlaceSearchHit) -> Bool {
        guard let prefectures else {
            return true
        }
        if let prefecture = Self.prefecture(named: hit.administrativeArea) {
            return prefectures.contains(prefecture)
        }
        return bounds.contains(latitude: hit.latitude, longitude: hit.longitude)
    }

    /// `administrativeArea` の値を、47 の都道府県の名前（「東京都」の形）にする。「東京」のように「都」「府」「県」が無くても当てる。
    /// 都道府県でない・無いときは nil
    /// - Parameter name: `MKPlacemark.administrativeArea` の値
    static func prefecture(named name: String?) -> String? {
        guard let name = name.map(NameValidation.trimWhitespace), !name.isEmpty else {
            return nil
        }
        return allPrefectures.first { $0 == name || shortName(of: $0) == name }
    }

    /// 都道府県の名前から「都」「府」「県」を外した名前（北海道はそのまま）
    private static func shortName(of prefecture: String) -> String {
        guard let last = prefecture.last, "都府県".contains(last) else {
            return prefecture
        }
        return String(prefecture.dropLast())
    }
}

/// 緯度・経度の矩形（検索の範囲。北緯・東経の度）
nonisolated struct SearchBounds: Equatable, Sendable {
    /// 南の端の緯度
    let minLatitude: Double
    /// 北の端の緯度
    let maxLatitude: Double
    /// 西の端の経度
    let minLongitude: Double
    /// 東の端の経度
    let maxLongitude: Double

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
