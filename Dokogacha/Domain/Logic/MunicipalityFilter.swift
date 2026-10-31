//
//  MunicipalityFilter.swift
//  Dokogacha
//
//  S-08 の市区町村を選ぶシートの、名前・よみでの絞り込みと五十音の行の見出し（Issue #160）。
//

import Foundation

/// 五十音の行ごとの市区町村（シートの見出しと、その下の行）
nonisolated struct KanaSection: Identifiable, Equatable, Sendable {
    /// 行の頭の字（「あ」「か」…「わ」）。見出しは「あ行」
    let row: String
    /// 行の市区町村（並びは元の一覧のまま）
    let municipalities: [Municipality]

    var id: String {
        row
    }
}

/// 市区町村の一覧の絞り込みと、五十音の行の分け方
nonisolated enum MunicipalityFilter {
    /// 五十音の行（頭の字と、その行の字）
    static let kanaRows: [(row: String, letters: String)] = [
        ("あ", "あいうえお"), ("か", "かきくけこ"), ("さ", "さしすせそ"), ("た", "たちつてと"), ("な", "なにぬねの"),
        ("は", "はひふへほ"), ("ま", "まみむめも"), ("や", "やゆよ"), ("ら", "らりるれろ"), ("わ", "わをん")
    ]

    /// 小さい字 → 大きい字
    private static let smallKana: [Character: Character] = [
        "ぁ": "あ", "ぃ": "い", "ぅ": "う", "ぇ": "え", "ぉ": "お", "っ": "つ", "ゃ": "や", "ゅ": "ゆ", "ょ": "よ", "ゎ": "わ"
    ]

    /// 語に合う市区町村（並びは保つ）。名前（漢字）か、よみ（ひらがな・カタカナ・半角カナのどれで打っても）に語を含めば合う。
    /// 空白だけ・空の語ならすべて
    /// - Parameters:
    ///   - municipalities: 都道府県の市区町村
    ///   - query: 入力した語
    static func filter(_ municipalities: [Municipality], query: String) -> [Municipality] {
        let key = searchKey(query)
        guard !key.isEmpty else {
            return municipalities
        }
        return municipalities.filter { municipality in
            searchKey(municipality.name).contains(key) || searchKey(municipality.kana).contains(key)
        }
    }

    /// 比べる形にそろえた語（空白を外し、半角・全角をそろえ、カタカナをひらがなに、「ヶ」と「ケ」などの書き分けをそろえる）
    static func searchKey(_ text: String) -> String {
        let normalized = PlaceLocality.normalized(text).lowercased()
        return normalized.applyingTransform(.hiraganaToKatakana, reverse: true) ?? normalized
    }

    /// 五十音の行ごとにまとめる（行の順。行の中の並びは元の一覧のまま）
    /// - Parameter municipalities: よみの五十音順に並べた市区町村
    static func sections(_ municipalities: [Municipality]) -> [KanaSection] {
        let grouped = Dictionary(grouping: municipalities) { kanaRow(of: $0.kana) }
        let rows = kanaRows.map(\.row) + ["他"]
        return rows.compactMap { row in
            grouped[row].map { KanaSection(row: row, municipalities: $0) }
        }
    }

    /// よみの頭の字の行（「が」「ぱ」は「か」「は」の行、小さい字は大きい字の行）。ひらがなでなければ「他」
    /// - Parameter kana: よみ（ひらがな）
    static func kanaRow(of kana: String) -> String {
        guard let head = kana.first else {
            return "他"
        }
        // 濁点・半濁点を外した字（「が」→「か」「ゔ」→「う」）。分解した字は 1 つの Character のままなので、最初のコードポイントを取る
        guard let scalar = String(head).decomposedStringWithCanonicalMapping.unicodeScalars.first else {
            return "他"
        }
        let base = smallKana[Character(scalar)] ?? Character(scalar)
        return kanaRows.first { $0.letters.contains(base) }?.row ?? "他"
    }
}
