//
//  PrefectureTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の検索のエリアの都道府県（`Prefecture`）を確かめる: 47 の並びと地方・検索の矩形に県庁と端の町が入る・名前の当て方（Issue #160）
struct PrefectureTests {
    /// 都道府県の中の町（緯度・経度）
    nonisolated struct Town: Sendable, CustomTestStringConvertible {
        let code: Int
        let name: String
        let latitude: Double
        let longitude: Double

        var testDescription: String {
            name
        }

        init(_ code: Int, _ name: String, _ latitude: Double, _ longitude: Double) {
            self.code = code
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// 47 の都道府県庁（都道府県コードの順）。矩形に入らないと、その都道府県を選んでも県庁の町が見つからない
    nonisolated static let capitals: [Town] = [
        Town(1, "札幌", 43.06, 141.35), Town(2, "青森", 40.82, 140.74), Town(3, "盛岡", 39.70, 141.15),
        Town(4, "仙台", 38.27, 140.87), Town(5, "秋田", 39.72, 140.10), Town(6, "山形", 38.24, 140.36),
        Town(7, "福島", 37.75, 140.47), Town(8, "水戸", 36.34, 140.45), Town(9, "宇都宮", 36.57, 139.88),
        Town(10, "前橋", 36.39, 139.06), Town(11, "さいたま", 35.86, 139.65), Town(12, "千葉", 35.60, 140.12),
        Town(13, "新宿", 35.69, 139.69), Town(14, "横浜", 35.45, 139.64), Town(15, "新潟", 37.90, 139.02),
        Town(16, "富山", 36.70, 137.21), Town(17, "金沢", 36.59, 136.63), Town(18, "福井", 36.07, 136.22),
        Town(19, "甲府", 35.66, 138.57), Town(20, "長野", 36.65, 138.18), Town(21, "岐阜", 35.39, 136.72),
        Town(22, "静岡", 34.98, 138.38), Town(23, "名古屋", 35.18, 136.91), Town(24, "津", 34.73, 136.51),
        Town(25, "大津", 35.00, 135.87), Town(26, "京都", 35.02, 135.76), Town(27, "大阪", 34.69, 135.52),
        Town(28, "神戸", 34.69, 135.18), Town(29, "奈良", 34.69, 135.83), Town(30, "和歌山", 34.23, 135.17),
        Town(31, "鳥取", 35.50, 134.24), Town(32, "松江", 35.47, 133.05), Town(33, "岡山", 34.66, 133.93),
        Town(34, "広島", 34.40, 132.46), Town(35, "山口", 34.19, 131.47), Town(36, "徳島", 34.07, 134.56),
        Town(37, "高松", 34.34, 134.04), Town(38, "松山", 33.84, 132.77), Town(39, "高知", 33.56, 133.53),
        Town(40, "福岡", 33.61, 130.42), Town(41, "佐賀", 33.25, 130.30), Town(42, "長崎", 32.74, 129.87),
        Town(43, "熊本", 32.79, 130.74), Town(44, "大分", 33.24, 131.61), Town(45, "宮崎", 31.91, 131.42),
        Town(46, "鹿児島", 31.56, 130.56), Town(47, "那覇", 26.21, 127.68)
    ]

    /// 端の町と、矩形に入れた近くの島
    nonisolated static let edgeTowns: [Town] = [
        Town(1, "稚内", 45.42, 141.67), Town(1, "根室", 43.33, 145.58), Town(1, "函館", 41.77, 140.73),
        Town(2, "大間", 41.53, 140.91), Town(6, "飛島", 39.19, 139.55), Town(9, "日光", 36.75, 139.60),
        Town(10, "草津", 36.62, 138.60), Town(11, "秩父", 35.99, 139.09), Town(12, "銚子", 35.73, 140.83),
        Town(12, "館山", 34.99, 139.87), Town(13, "奥多摩", 35.81, 139.10), Town(13, "羽田", 35.55, 139.78),
        Town(14, "箱根", 35.23, 139.11), Town(14, "三崎", 35.14, 139.62), Town(15, "佐渡（両津）", 38.08, 138.44),
        Town(15, "糸魚川", 37.04, 137.86), Town(17, "珠洲", 37.44, 137.26), Town(20, "軽井沢", 36.35, 138.60),
        Town(21, "白川郷", 36.26, 136.91), Town(22, "下田", 34.68, 138.95), Town(22, "熱海", 35.10, 139.07),
        Town(23, "伊良湖", 34.58, 137.02), Town(24, "熊野", 33.89, 136.10), Town(28, "洲本", 34.34, 134.89),
        Town(30, "串本", 33.47, 135.78), Town(32, "隠岐（西郷）", 36.20, 133.32), Town(35, "下関", 33.96, 130.94),
        Town(37, "小豆島", 34.49, 134.19), Town(38, "佐田岬", 33.34, 132.02), Town(39, "足摺岬", 32.72, 133.02),
        Town(39, "室戸", 33.29, 134.15), Town(42, "対馬（厳原）", 34.20, 129.29), Town(42, "五島（福江）", 32.70, 128.84),
        Town(43, "天草", 32.46, 130.19), Town(46, "屋久島", 30.42, 130.57), Town(46, "種子島", 30.73, 131.00),
        Town(46, "甑島", 31.83, 129.87), Town(47, "石垣", 24.34, 124.16)
    ]

    /// 47 の都道府県を、都道府県コード 1〜47 の順に 1 回ずつ持つ。名前は重ならない
    @Test
    func allPrefecturesInCodeOrder() {
        #expect(Prefecture.all.map(\.code) == Array(1...47))
        #expect(Set(Prefecture.all.map(\.name)).count == 47)
        #expect(Set(Prefecture.all.map(\.romanizedName)).count == 47)
        #expect(Prefecture.code(13)?.name == "東京都")
        #expect(Prefecture.code(0) == nil)
        #expect(Prefecture.code(48) == nil)
    }

    /// 都道府県の矩形に、県庁の町が入る
    @Test(arguments: Self.capitals)
    func boundsContainCapital(town: Town) throws {
        let prefecture = try #require(Prefecture.code(town.code))
        #expect(prefecture.bounds.contains(latitude: town.latitude, longitude: town.longitude), "\(town.name) が \(prefecture.name) の範囲の外")
    }

    /// 都道府県の矩形に、端の町と近くの島が入る
    @Test(arguments: Self.edgeTowns)
    func boundsContainEdgeTown(town: Town) throws {
        let prefecture = try #require(Prefecture.code(town.code))
        #expect(prefecture.bounds.contains(latitude: town.latitude, longitude: town.longitude), "\(town.name) が \(prefecture.name) の範囲の外")
    }

    /// 遠くの離島は入れない（矩形の中心を本土に置くため。島の町村を選べば探せる）
    @Test
    func boundsExcludeRemoteIslands() throws {
        let tokyo = try #require(Prefecture.code(13))
        let kagoshima = try #require(Prefecture.code(46))
        // 八丈島・父島・奄美大島
        #expect(!tokyo.bounds.contains(latitude: 33.11, longitude: 139.79))
        #expect(!tokyo.bounds.contains(latitude: 27.09, longitude: 142.19))
        #expect(!kagoshima.bounds.contains(latitude: 28.38, longitude: 129.49))
    }

    /// 都道府県の矩形は、全国の矩形の中にあり、南北・西東の向きが正しい
    @Test
    func boundsAreInsideNationwide() {
        let nationwide = SearchArea.nationwide.bounds
        for prefecture in Prefecture.all {
            let bounds = prefecture.bounds
            #expect(bounds.minLatitude < bounds.maxLatitude && bounds.minLongitude < bounds.maxLongitude, "\(prefecture.name)")
            #expect(nationwide.contains(latitude: bounds.minLatitude, longitude: bounds.minLongitude), "\(prefecture.name)")
            #expect(nationwide.contains(latitude: bounds.maxLatitude, longitude: bounds.maxLongitude), "\(prefecture.name)")
        }
    }

    /// 北海道・沖縄の矩形は、地方の矩形と同じ
    @Test
    func soloPrefecturesUseAreaBounds() {
        #expect(SearchArea.hokkaido.soloPrefecture?.bounds == SearchArea.hokkaido.bounds)
        #expect(SearchArea.okinawa.soloPrefecture?.bounds == SearchArea.okinawa.bounds)
    }

    /// チップに出す短い名前は「都」「府」「県」を外す（北海道はそのまま）
    @Test
    func shortNames() {
        #expect(Prefecture.code(13)?.shortName == "東京")
        #expect(Prefecture.code(26)?.shortName == "京都")
        #expect(Prefecture.code(27)?.shortName == "大阪")
        #expect(Prefecture.code(14)?.shortName == "神奈川")
        #expect(Prefecture.code(1)?.shortName == "北海道")
    }

    /// `administrativeArea` の値は、正式な名前・「都」「府」「県」の無い名前・英語の端末のローマ字で当てる。都道府県でないものは nil
    @Test
    func namedMatchesJapaneseAndRomanizedNames() {
        #expect(Prefecture.named("東京都")?.code == 13)
        #expect(Prefecture.named("東京")?.code == 13)
        #expect(Prefecture.named("京都")?.code == 26)
        #expect(Prefecture.named(" 大阪府 ")?.code == 27)
        #expect(Prefecture.named("北海道")?.code == 1)
        #expect(Prefecture.named("Tokyo")?.code == 13)
        #expect(Prefecture.named("Kanagawa")?.code == 14)
        #expect(Prefecture.named("Hyōgo")?.code == 28)
        #expect(Prefecture.named("Ōita")?.code == 44)
        #expect(Prefecture.named("Tokyo-to")?.code == 13)
        #expect(Prefecture.named("Osaka-fu")?.code == 27)
        #expect(Prefecture.named("Kyoto")?.code == 26)
        #expect(Prefecture.named("Chiba Prefecture")?.code == 12)
        #expect(Prefecture.named("京") == nil)
        #expect(Prefecture.named("Seoul") == nil)
        #expect(Prefecture.named("") == nil)
        #expect(Prefecture.named(nil) == nil)
    }
}
