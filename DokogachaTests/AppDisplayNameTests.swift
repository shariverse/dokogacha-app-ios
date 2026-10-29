//
//  AppDisplayNameTests.swift
//  DokogachaTests
//

import Foundation
import Testing

/// ホーム画面のアイコンの下に出るアプリ名（`CFBundleDisplayName`）が、言語ごとに決めた値でアプリに入っていることを確かめる（Discussion #147）。
///
/// 値は `Dokogacha/InfoPlist.xcstrings` にあり、ビルドで `<言語>.lproj/InfoPlist.strings` に書き出される。
/// 鍵の書き間違い・言語の抜けがあってもビルドは通り、ホーム画面の名前が `PRODUCT_NAME` の「Dokogacha」に戻るだけなので、ここで検出する
struct AppDisplayNameTests {
    /// 言語ごとのホーム画面のアプリ名。日本語は App Store の日本語のアプリ名とそろえる
    nonisolated enum Expected {
        /// 日本語の環境の名前（依頼 #146）
        static let japanese = "ドコガチャ"
        /// 英語の環境の名前（Discussion #147 の Q1。今までの `PRODUCT_NAME` と同じ）
        static let english = "Dokogacha"
    }

    /// `<言語>.lproj/InfoPlist.strings` の `CFBundleDisplayName` を読む
    static func displayName(forLocalization localization: String) throws -> String {
        let path = try #require(
            Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: localization)
        )
        let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        return try #require(strings["CFBundleDisplayName"])
    }

    @Test
    func japaneseDisplayNameIsDokogachaInKatakana() throws {
        #expect(try Self.displayName(forLocalization: "ja") == Expected.japanese)
    }

    @Test
    func englishDisplayNameStaysDokogacha() throws {
        #expect(try Self.displayName(forLocalization: "en") == Expected.english)
    }

    /// 足したのは `en` で、開発言語は日本語のまま（pbxproj の `developmentRegion = ja`）
    @Test
    func developmentRegionIsJapanese() {
        #expect(Bundle.main.developmentLocalization == "ja")
    }
}
