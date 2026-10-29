//
//  DemoPlaceSearchService.swift
//  Dokogacha
//

import MapKit

/// 決まった場所の一覧から探す擬似の場所検索（Unit テストのホスト・`-uiTesting`・撮影モード・プレビュー）。
///
/// ネットワークに出ず、同じ語なら必ず同じ結果を返す（UI テストと撮影を揺らさないため）。
/// 結果は MapKit の実装と同じ `SearchedPlace.make` で作るので、カテゴリの判定（MapKit のカテゴリ・場所名）も同じ道を通る。
/// 語は、場所名・都道府県・市区町村・場所ごとの語（クイックカテゴリの「水族館」「自然」「グルメ」「テーマパーク」「街歩き」など）に含まれれば当たる。
/// エリアは MapKit の実装と同じ `SearchArea.keeps` で絞る（場所は関東・中部のものだけなので、ほかの地方では見つからない）。
///
/// デモのルーム（`room-with-candidates`）の候補と同じ場所（サンシャイン水族館・明治神宮・江の島）を含めてあり、
/// 「追加済み」・重複の確認を確かめられる。
nonisolated struct DemoPlaceSearchService: PlaceSearchService {
    /// デモの場所 1 件（MapKit の結果の値と、検索で当たる語）
    struct Entry: Sendable {
        /// MapKit の結果の値
        let hit: PlaceSearchHit
        /// 検索で当たる語（場所名・エリアのほかに）
        let keywords: [String]
    }

    /// すみだ水族館の ID（UI テストで選ぶ）
    static let sumidaAquariumID = "demo-place-sumida-aquarium"
    /// サンシャイン水族館の ID（デモのルームのはるかの候補と同じ場所）
    static let sunshineAquariumID = "demo-place-sunshine-aquarium"

    /// デモの場所（検索の結果はこの順）
    static let entries: [Entry] = [
        Entry(
            hit: PlaceSearchHit(
                name: "すみだ水族館",
                administrativeArea: "東京都",
                locality: "墨田区",
                latitude: 35.710_1,
                longitude: 139.810_7,
                mapItemID: sumidaAquariumID,
                pointOfInterestCategory: .aquarium
            ),
            keywords: ["水族館"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "サンシャイン水族館",
                administrativeArea: "東京都",
                locality: "豊島区",
                latitude: 35.728_9,
                longitude: 139.719_7,
                mapItemID: sunshineAquariumID,
                pointOfInterestCategory: .aquarium
            ),
            keywords: ["水族館"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "しながわ水族館",
                administrativeArea: "東京都",
                locality: "品川区",
                latitude: 35.588_7,
                longitude: 139.735_6,
                mapItemID: "demo-place-shinagawa-aquarium",
                pointOfInterestCategory: .aquarium
            ),
            keywords: ["水族館"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "鴨川シーワールド",
                administrativeArea: "千葉県",
                locality: "鴨川市",
                latitude: 35.115_7,
                longitude: 140.121_8,
                mapItemID: "demo-place-kamogawa",
                pointOfInterestCategory: .aquarium
            ),
            keywords: ["水族館", "海"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "高尾山",
                administrativeArea: "東京都",
                locality: "八王子市",
                latitude: 35.625_1,
                longitude: 139.243_7,
                mapItemID: "demo-place-takao",
                pointOfInterestCategory: .nationalPark
            ),
            keywords: ["自然", "山"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "箱根 大涌谷",
                administrativeArea: "神奈川県",
                locality: "箱根町",
                latitude: 35.244_1,
                longitude: 139.019_6,
                mapItemID: "demo-place-owakudani",
                pointOfInterestCategory: .park
            ),
            keywords: ["自然"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "日光東照宮",
                administrativeArea: "栃木県",
                locality: "日光市",
                latitude: 36.758_1,
                longitude: 139.598_9,
                mapItemID: "demo-place-nikko",
                pointOfInterestCategory: nil
            ),
            keywords: ["寺社"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "明治神宮",
                administrativeArea: "東京都",
                locality: "渋谷区",
                latitude: 35.676_4,
                longitude: 139.699_3,
                mapItemID: "demo-place-meiji",
                pointOfInterestCategory: nil
            ),
            keywords: ["寺社"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "江の島",
                administrativeArea: "神奈川県",
                locality: "藤沢市",
                latitude: 35.299_4,
                longitude: 139.480_0,
                mapItemID: "demo-place-enoshima",
                pointOfInterestCategory: .beach
            ),
            keywords: ["海"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "由比ヶ浜海水浴場",
                administrativeArea: "神奈川県",
                locality: "鎌倉市",
                latitude: 35.310_4,
                longitude: 139.545_3,
                mapItemID: "demo-place-yuigahama",
                pointOfInterestCategory: .beach
            ),
            keywords: ["海"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "富士急ハイランド",
                administrativeArea: "山梨県",
                locality: "富士吉田市",
                latitude: 35.487_2,
                longitude: 138.780_3,
                mapItemID: "demo-place-fujiq",
                pointOfInterestCategory: .amusementPark
            ),
            keywords: ["テーマパーク"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "築地場外市場",
                administrativeArea: "東京都",
                locality: "中央区",
                latitude: 35.665_4,
                longitude: 139.770_6,
                mapItemID: "demo-place-tsukiji",
                pointOfInterestCategory: .foodMarket
            ),
            keywords: ["グルメ"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "谷中銀座商店街",
                administrativeArea: "東京都",
                locality: "台東区",
                latitude: 35.727_6,
                longitude: 139.766_4,
                mapItemID: "demo-place-yanaka",
                pointOfInterestCategory: .store
            ),
            keywords: ["街歩き"]
        ),
        Entry(
            hit: PlaceSearchHit(
                name: "横浜赤レンガ倉庫",
                administrativeArea: "神奈川県",
                locality: "横浜市",
                latitude: 35.452_6,
                longitude: 139.642_8,
                mapItemID: "demo-place-redbrick",
                pointOfInterestCategory: nil
            ),
            keywords: ["街歩き"]
        )
    ]

    func search(_ query: String, in area: SearchArea) async throws -> [SearchedPlace] {
        Self.results(for: query, in: area)
    }

    /// 語に当たる、エリアの中のデモの場所（一覧の順）。空の語では何も返さない
    /// - Parameters:
    ///   - query: 検索する語
    ///   - area: 探すエリア（既定は全国）
    static func results(for query: String, in area: SearchArea = .nationwide) -> [SearchedPlace] {
        let query = NameValidation.trimWhitespace(query)
        guard !query.isEmpty else {
            return []
        }
        return entries
            .filter { entry in
                let words = [entry.hit.name, entry.hit.administrativeArea, entry.hit.locality].compactMap(\.self) + entry.keywords
                return words.contains { $0.contains(query) } && area.keeps(entry.hit)
            }
            .compactMap { SearchedPlace.make($0.hit) }
    }
}
