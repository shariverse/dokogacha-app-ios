//
//  MunicipalityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の市区町村の一覧（`MunicipalityCatalog`）と、シートの絞り込み・五十音の行（`MunicipalityFilter`）を確かめる（Issue #160）
struct MunicipalityTests {
    /// 東京都
    static func tokyo() throws -> Prefecture {
        try #require(Prefecture.code(13))
    }

    // MARK: - 同梱の一覧

    /// 同梱の一覧は、総務省のコード表の市町村 1,718・特別区 23（北方領土の 6 村を除く）を、47 の都道府県に分けて持つ
    @Test
    func bundledCatalogCoversJapan() throws {
        let catalog = MunicipalityCatalog.bundled
        #expect(catalog.count == 1_741)
        #expect(Prefecture.all.allSatisfy { !catalog.municipalities(in: $0).isEmpty })
        #expect(Prefecture.all.map { catalog.municipalities(in: $0).count }.reduce(0, +) == 1_741)
        // 東京は 23 区・26 市・5 町・8 村、北海道は 179（北方領土の 6 村を除く）
        #expect(catalog.municipalities(in: try Self.tokyo()).count == 62)
        #expect(catalog.municipalities(in: try #require(Prefecture.code(1))).count == 179)
        #expect(catalog.municipality(code: "016969") == nil)
    }

    /// 団体コードで引け、都道府県はコードの上 2 桁。政令指定都市は市全体で 1 つ、郡は名前に付けない
    @Test
    func lookUpByCode() throws {
        let catalog = MunicipalityCatalog.bundled
        let toshima = try #require(catalog.municipality(code: "131164"))
        #expect(toshima.name == "豊島区")
        #expect(toshima.kana == "としまく")
        #expect(toshima.prefecture?.name == "東京都")
        #expect(catalog.municipality(code: "141003")?.name == "横浜市")
        #expect(catalog.municipality(code: "143821")?.name == "箱根町")
        #expect(catalog.municipality(code: "999999") == nil)
    }

    /// 都道府県の中では、よみの五十音順（濁点は清音の後）に並ぶ
    @Test
    func sortedByKana() throws {
        let tokyo = MunicipalityCatalog.bundled.municipalities(in: try Self.tokyo())
        #expect(tokyo.prefix(3).map(\.name) == ["青ヶ島村", "昭島市", "あきる野市"])
        let kanas = tokyo.map(\.kana)
        #expect(kanas == kanas.sorted { $0.compare($1, locale: Locale(identifier: "ja_JP")) == .orderedAscending })
    }

    /// 注記・見出し・形の違う行は読まない
    @Test
    func parsingSkipsCommentsAndMalformedLines() throws {
        let catalog = MunicipalityCatalog(tsv: """
        # 注記
        code\tname\tkana
        131164\t豊島区\tとしまく
        13116\t短い\tみじかい
        131172\t北区
        13118x\t英字\tえいじ
        131181\t荒川区\tあらかわく
        """)
        #expect(catalog.count == 2)
        #expect(catalog.municipalities(in: try Self.tokyo()).map(\.name) == ["荒川区", "豊島区"])
    }

    // MARK: - 絞り込み

    /// 名前（漢字）か、よみ（ひらがな・カタカナ・半角カナ）を含めば合う。空の語ならすべて
    @Test
    func filterByNameOrKana() throws {
        let tokyo = MunicipalityCatalog.bundled.municipalities(in: try Self.tokyo())
        #expect(MunicipalityFilter.filter(tokyo, query: "豊島").map(\.name) == ["豊島区"])
        // よみの「としま」は豊島区（としまく）と利島村（としまむら）に合う
        #expect(MunicipalityFilter.filter(tokyo, query: "としま").map(\.name) == ["豊島区", "利島村"])
        #expect(MunicipalityFilter.filter(tokyo, query: "トシマク").map(\.name) == ["豊島区"])
        #expect(MunicipalityFilter.filter(tokyo, query: "ﾄｼﾏﾑﾗ").map(\.name) == ["利島村"])
        #expect(MunicipalityFilter.filter(tokyo, query: " しぶや ").map(\.name) == ["渋谷区"])
        #expect(MunicipalityFilter.filter(tokyo, query: "  ").count == 62)
        let osaka = MunicipalityFilter.filter(tokyo, query: "大阪")
        #expect(osaka.isEmpty)
    }

    /// 「ヶ」と「ケ」の書き分け、「桧」と「檜」などの字の違いは区別しない
    @Test
    func filterIgnoresVariantCharacters() throws {
        let chiba = MunicipalityCatalog.bundled.municipalities(in: try #require(Prefecture.code(12)))
        #expect(MunicipalityFilter.filter(chiba, query: "鎌ヶ谷").map(\.name) == ["鎌ケ谷市"])
        let tokyo = MunicipalityCatalog.bundled.municipalities(in: try Self.tokyo())
        #expect(MunicipalityFilter.filter(tokyo, query: "桧原").map(\.name) == ["檜原村"])
    }

    // MARK: - 五十音の行

    /// よみの頭の字の行。濁点・半濁点・小さい字は、元の字の行
    @Test(arguments: [
        ("あきしまし", "あ"), ("がまごおりし", "か"), ("ぱ", "は"), ("ゔ", "あ"), ("ぁ", "あ"),
        ("ゆすはらちょう", "や"), ("わこうし", "わ"), ("", "他"), ("ABC", "他")
    ])
    func kanaRow(kana: String, row: String) {
        #expect(MunicipalityFilter.kanaRow(of: kana) == row)
    }

    /// 行ごとのまとまりは五十音の行の順で、行の中の並びは元のまま
    @Test
    func sectionsInKanaRowOrder() throws {
        let tokyo = MunicipalityCatalog.bundled.municipalities(in: try Self.tokyo())
        let sections = MunicipalityFilter.sections(tokyo)
        // 東京の市区町村のよみは「や」「ら」「わ」の行で始まらないので、その行は出さない
        #expect(sections.map(\.row) == ["あ", "か", "さ", "た", "な", "は", "ま"])
        #expect(sections.flatMap(\.municipalities) == tokyo)
        #expect(sections.first?.municipalities.first?.name == "青ヶ島村")
    }
}
