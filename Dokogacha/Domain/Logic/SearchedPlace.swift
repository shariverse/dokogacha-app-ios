//
//  SearchedPlace.swift
//  Dokogacha
//
//  場所検索（S-08「場所を探す」）の結果 1 件と、MapKit の値からの作り方（02 の §3.1「保存する情報」）。
//

import MapKit

/// 場所検索の結果 1 件（カテゴリを判定済みの場所）。
///
/// MapKit の型（`MKMapItem`）を持たないのは、画面の Model とテストを MapKit の検索から切り離し、
/// 擬似の検索（`DemoPlaceSearchService`）でも同じ値を作れるようにするため。
nonisolated struct SearchedPlace: Identifiable, Equatable, Hashable, Sendable {
    /// 結果の ID（MapKit の識別子があればそれ、無ければ場所名と座標から作る。画面の行の ID と UI テストの ID に使う）
    let id: String
    /// 保存する場所（`candidates.place`）
    let place: Place
    /// 自動で判定したカテゴリ（02 の §3.1 の対応表。S-09 で選び直せる）
    let category: PlaceCategory

    /// MapKit の検索結果の値から作る。場所名が空・長すぎるなど、投稿できない（`CandidateRules.validatedPlace` が断る）結果は nil。
    ///
    /// - エリアは `PlaceArea.text` で「東京・豊島区」の形にする。市区町村は `PlaceLocality.displayName` で形をそろえる
    ///   （「中区, 横浜市」→「横浜市中区」、「足柄下郡箱根町」→「箱根町」）。長すぎるときは都道府県だけ、それでも長ければ空にする
    /// - カテゴリは `PlaceCategory.classify`（MapKit のカテゴリ → 場所名の「神社」「寺」「宮」→ 街歩き）
    /// - MapKit の識別子は、保存できる形（`CandidateRules.isAcceptableMapItemID`）のときだけ持つ
    /// - Parameter hit: MapKit の検索結果から取り出した値
    static func make(_ hit: PlaceSearchHit) -> Self? {
        guard let name = hit.name else {
            return nil
        }
        let locality = PlaceLocality.displayName(locality: hit.locality, subLocality: hit.subLocality)
        let areaCandidates = [
            PlaceArea.text(administrativeArea: hit.administrativeArea, locality: locality),
            PlaceArea.text(administrativeArea: hit.administrativeArea, locality: nil),
            ""
        ]
        let area = areaCandidates.first {
            CandidateRules.validatedOptionalText($0, length: DomainConstants.Limits.placeAreaLength) != nil
        } ?? ""
        let identifier = hit.mapItemID.flatMap { CandidateRules.isAcceptableMapItemID($0) ? $0 : nil }
        let raw = Place(name: name, area: area, latitude: hit.latitude, longitude: hit.longitude, mapItemId: identifier)
        guard let place = CandidateRules.validatedPlace(raw) else {
            return nil
        }
        return Self(
            id: identifier ?? "\(place.name)@\(place.latitude),\(place.longitude)",
            place: place,
            category: PlaceCategory.classify(pointOfInterestCategory: hit.pointOfInterestCategory, placeName: place.name)
        )
    }

    /// 同じ ID の結果を、先に出たものだけ残して取り除く（並びは保つ）。
    ///
    /// MapKit は同じ場所を 2 件返すことがあり、そのままだと画面の行（`ForEach`）の ID が重なって表示が崩れる。
    /// ID が同じなら場所も同じ（識別子が同じ・名前と座標が同じ）なので、先の 1 件で足りる
    static func uniqued(_ places: [Self]) -> [Self] {
        var seen: Set<String> = []
        return places.filter { seen.insert($0.id).inserted }
    }
}

/// MapKit の検索結果 1 件から取り出した値（`MKMapItem` を画面の外に持ち出さないための写し）
nonisolated struct PlaceSearchHit: Sendable {
    /// 場所名（`MKMapItem.name`）
    var name: String?
    /// 都道府県（`MKPlacemark.administrativeArea`。「東京都」の形）
    var administrativeArea: String?
    /// 市区町村（`MKPlacemark.locality`。「豊島区」の形。政令指定都市・郡は形が揺れる（`PlaceLocality`））
    var locality: String?
    /// 市区町村の中の地名（`MKPlacemark.subLocality`。`locality` が郡・政令指定都市だけのときは、町村・区が入る）
    var subLocality: String?
    /// 緯度
    var latitude: Double
    /// 経度
    var longitude: Double
    /// MapKit の識別子（iOS 18 以降で取れたときだけ）
    var mapItemID: String?
    /// MapKit のカテゴリ（無ければ nil）
    var pointOfInterestCategory: MKPointOfInterestCategory?
}

/// エリアの表示（02 の §3.1「エリア表示（都道府県・市区町村。例「東京・豊島区」）」）。
nonisolated enum PlaceArea {
    /// 都道府県の名前の末尾から外す字（「東京都」→「東京」、「神奈川県」→「神奈川」、「大阪府」→「大阪」。「北海道」はそのまま）
    static let prefectureSuffixes: [Character] = ["都", "府", "県"]
    /// 都道府県と市区町村の区切り
    static let separator = "・"

    /// 都道府県と市区町村から「東京・豊島区」の形を作る。
    ///
    /// - 都道府県の末尾の「都」「府」「県」は外す（外すと 1 文字になるとき（「京都」など）は外さない）
    /// - 片方しか無ければその片方だけ。市区町村が都道府県と同じ名前なら 1 つにする
    /// - どちらも無ければ空
    static func text(administrativeArea: String?, locality: String?) -> String {
        let prefecture = administrativeArea.map(NameValidation.trimWhitespace).map(shortPrefecture) ?? ""
        let city = locality.map(NameValidation.trimWhitespace) ?? ""
        let parts = [prefecture, city].filter { !$0.isEmpty }
        if parts.count == 2, prefecture == city || administrativeArea.map(NameValidation.trimWhitespace) == city {
            return prefecture
        }
        return parts.joined(separator: separator)
    }

    /// 都道府県の名前から末尾の「都」「府」「県」を外す
    private static func shortPrefecture(_ name: String) -> String {
        guard let last = name.last, prefectureSuffixes.contains(last), name.count > 2 else {
            return name
        }
        return String(name.dropLast())
    }
}
