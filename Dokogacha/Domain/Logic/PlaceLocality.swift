//
//  PlaceLocality.swift
//  Dokogacha
//
//  MapKit の結果の市区町村（`MKPlacemark.locality`・`subLocality`）の読み方（Issue #160）。
//

import Foundation

/// MapKit の結果の市区町村を、同梱の市区町村の名前と突き合わせる。
///
/// `locality` は、同じ市区町村でも形がそろわない（Mac の MapKit で確かめた形）:
/// - 東京の 23 区・市・町村: 「渋谷区」「鎌ケ谷市」「箱根町」
/// - 政令指定都市: 「中区, 横浜市」「横浜市」（区は `subLocality`）「札幌市中央区」
/// - 郡の町村: 「足柄下郡箱根町」「箱根町」「足柄下郡」（町は `subLocality`）
/// - 英語の端末: 「Hakone, Ashigarashimo-Gun」「Shibuya」（日本語の名前と突き合わせられない）
nonisolated enum PlaceLocality {
    /// 名前の比べ方をそろえる字（MapKit と総務省の表で書き方が揺れうる字 → そろえた字）
    static let variantCharacters: [Character: Character] = [
        "ヶ": "ケ", "ヵ": "カ", "﨑": "崎", "髙": "高", "桧": "檜", "梼": "檮", "龍": "竜"
    ]

    /// 結果が市区町村に入るか。
    ///
    /// - 「横浜市」は「横浜市」「中区, 横浜市」「横浜市中区」に合う（政令指定都市の区）
    /// - 「箱根町」は「箱根町」「足柄下郡箱根町」と、`locality` が「足柄下郡」で `subLocality` が「箱根町」のものに合う
    /// - 「ヶ」と「ケ」などの書き分けは区別しない（`variantCharacters`）
    /// - Parameters:
    ///   - locality: `MKPlacemark.locality`
    ///   - subLocality: `MKPlacemark.subLocality`
    ///   - municipality: 市区町村の名前（「横浜市」「箱根町」）
    /// - Returns: 合うか。市区町村が無い・日本語でない（英語の端末など）で分からなければ nil
    static func matches(locality: String?, subLocality: String?, municipality: String) -> Bool? {
        var candidates = parts(of: locality)
        if candidates.contains(where: { $0.hasSuffix("郡") }), let subLocality = trimmed(subLocality) {
            candidates.append(subLocality)
        }
        let japanese = candidates.filter(isJapanese)
        guard !japanese.isEmpty else {
            return nil
        }
        let target = normalized(municipality)
        return japanese.contains { matches(normalized($0), target) }
    }

    /// 比べるために形をそろえた名前（前後と中の空白を外し、互換の字を合わせ、書き分けのある字をそろえる）
    static func normalized(_ name: String) -> String {
        let compatible = name.precomposedStringWithCompatibilityMapping
        return String(compatible.filter { !$0.isWhitespace }.map { variantCharacters[$0] ?? $0 })
    }

    /// 形をそろえた 2 つの名前が同じ市区町村か（政令指定都市の区・郡の町村を含む）
    private static func matches(_ part: String, _ target: String) -> Bool {
        if part == target {
            return true
        }
        // 札幌市中央区 → 札幌市
        if target.hasSuffix("市"), part.hasPrefix(target), part.dropFirst(target.count).hasSuffix("区") {
            return true
        }
        // 足柄下郡箱根町 → 箱根町（赤穂郡上郡町 → 上郡町）
        return part.hasSuffix(target) && part.dropLast(target.count).hasSuffix("郡")
    }

    /// `locality` を「,」「、」で区切った、空でない部分
    private static func parts(of locality: String?) -> [String] {
        guard let locality else {
            return []
        }
        return locality.split { $0 == "," || $0 == "、" }.compactMap { trimmed(String($0)) }
    }

    /// 前後の空白を外した値。空なら nil
    private static func trimmed(_ text: String?) -> String? {
        guard let text = text.map(NameValidation.trimWhitespace), !text.isEmpty else {
            return nil
        }
        return text
    }

    /// 日本語（ひらがな・カタカナ・漢字）を含むか
    private static func isJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
            default: false
            }
        }
    }
}
