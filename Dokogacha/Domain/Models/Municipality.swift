//
//  Municipality.swift
//  Dokogacha
//

import Foundation

/// 市区町村（S-08 の検索のエリアで、都道府県の次に任意で選ぶ。03 の S-08 の 6・Issue #160）。
///
/// 一覧は総務省の「都道府県コード及び市区町村コード」を加工して同梱したもの（`Resources/Municipalities.tsv`。`MunicipalityCatalog`）。
/// 政令指定都市は市全体で 1 つ（区は選べない）、東京の 23 区は 1 区ずつ。郡は名前に付けない（「箱根町」）
nonisolated struct Municipality: Hashable, Identifiable, Sendable {
    /// 団体コード（6 桁。上 2 桁が都道府県コード）
    let code: String
    /// 名前（「豊島区」「横浜市」「箱根町」）
    let name: String
    /// よみ（ひらがな。「としまく」）
    let kana: String

    var id: String {
        code
    }

    /// 都道府県コード（団体コードの上 2 桁）
    var prefectureCode: Int {
        Int(code.prefix(2)) ?? 0
    }

    /// 都道府県
    var prefecture: Prefecture? {
        Prefecture.code(prefectureCode)
    }
}

/// 同梱の市区町村の一覧（`Resources/Municipalities.tsv`。`Tools/make_municipalities.py` で作る）。
///
/// 1 行に「団体コード・名前・よみ」をタブで区切って並べ、`#` で始まる行（出典などの注記）と見出しの行は読まない。
/// 都道府県ごとに、よみの五十音順（日本語の照合順。濁点は清音の後）に並べて持つ
nonisolated struct MunicipalityCatalog: Sendable {
    /// 同梱の一覧のファイル名（アプリのバンドルの直下に入る）
    static let resourceName = "Municipalities"
    /// 同梱の一覧のファイルの拡張子
    static let resourceExtension = "tsv"

    /// アプリに同梱した一覧（読めなければ空。空のときは S-08 で市区町村を選べない）
    static let bundled: Self = {
        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return Self(tsv: "")
        }
        return Self(tsv: text)
    }()

    /// 都道府県コードごとの市区町村（よみの五十音順）
    private let byPrefecture: [Int: [Municipality]]
    /// 団体コードごとの市区町村
    private let byCode: [String: Municipality]

    /// - Parameter tsv: 一覧の中身（団体コード・名前・よみをタブで区切った行）
    init(tsv: String) {
        let municipalities = tsv.split(whereSeparator: \.isNewline).compactMap(Self.municipality(line:))
        byCode = Dictionary(municipalities.map { ($0.code, $0) }) { first, _ in first }
        byPrefecture = Dictionary(grouping: municipalities, by: \.prefectureCode).mapValues { items in
            items.sorted(by: Self.inKanaOrder)
        }
    }

    /// 市区町村の数
    var count: Int {
        byCode.count
    }

    /// 都道府県の市区町村（よみの五十音順）
    func municipalities(in prefecture: Prefecture) -> [Municipality] {
        byPrefecture[prefecture.code] ?? []
    }

    /// 団体コードの市区町村。一覧に無ければ nil（合併などで無くなったコード）
    func municipality(code: String) -> Municipality? {
        byCode[code]
    }

    /// 1 行を市区町村にする。注記・見出し・形の違う行は nil
    private static func municipality(line: Substring) -> Municipality? {
        guard !line.hasPrefix("#") else {
            return nil
        }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard
            columns.count == 3,
            columns[0].count == 6,
            columns[0].allSatisfy(\.isASCII),
            columns[0].allSatisfy(\.isNumber),
            !columns[1].isEmpty,
            !columns[2].isEmpty
        else {
            return nil
        }
        return Municipality(code: columns[0], name: columns[1], kana: columns[2])
    }

    /// よみの五十音順（日本語の照合順。同じよみなら団体コードの順）
    private static func inKanaOrder(_ lhs: Municipality, _ rhs: Municipality) -> Bool {
        switch lhs.kana.compare(rhs.kana, locale: Locale(identifier: "ja_JP")) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.code < rhs.code
        }
    }
}
