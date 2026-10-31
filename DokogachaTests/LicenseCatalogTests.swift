//
//  LicenseCatalogTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-15 のライセンスの画面の一覧（同梱のフォントの OFL と主要なライブラリ）が、アプリに入った全文のファイルを読めることを確かめる
/// （06 の §5「フォントの OFL ライセンス表記」）
struct LicenseCatalogTests {
    /// すべての行の全文が、アプリのバンドルから読める（Unit テストのホストはアプリ）
    @Test(arguments: LicenseCatalog.all)
    func licenseTextIsBundled(entry: LicenseEntry) throws {
        let text = try #require(LicenseCatalog.text(of: entry))
        #expect(!text.isEmpty)
    }

    /// 全文の中身がライセンスの種類と合う
    @Test(arguments: LicenseCatalog.all)
    func licenseTextMatchesKind(entry: LicenseEntry) throws {
        let text = try #require(LicenseCatalog.text(of: entry))
        let marker = switch entry.kind {
        case .ofl: "SIL OPEN FONT LICENSE Version 1.1"
        case .apache2: "Apache License"
        case .bsd3: "Redistribution and use in source and binary forms"
        case .zlib: "This software is provided 'as-is'"
        case .pdl1: "公共データ利用規約（第1.0版）"
        }
        #expect(text.contains(marker))
    }

    /// 同梱のフォントは 2 つとも OFL で、全文の先頭の著作権の表示と同じものを出す
    @Test
    func bundledFontsShowTheirCopyright() throws {
        #expect(LicenseCatalog.fonts.map(\.name) == ["Mochiy Pop One", "Zen Maru Gothic"])
        for entry in LicenseCatalog.fonts {
            #expect(entry.kind == .ofl)
            let text = try #require(LicenseCatalog.text(of: entry))
            #expect(text.hasPrefix(entry.notice))
        }
    }

    /// 主要なライブラリ（Firebase・Google Mobile Ads）が入っていて、ID は重ならない
    @Test
    func librariesIncludeFirebaseAndGoogleMobileAds() {
        let names = LicenseCatalog.libraries.map(\.name)
        #expect(names.contains("Firebase Apple SDK"))
        #expect(names.contains("Google Mobile Ads SDK"))
        let ids = LicenseCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// 同梱の市区町村の一覧は、出典（総務省のコード表を加工したこと）と利用条件（PDL1.0）の URL を出す（公共データ利用規約の出典の記載）
    @Test
    func municipalityDataShowsSourceAndTerms() throws {
        let entry = try #require(LicenseCatalog.data.first { $0.id == "municipalities" })
        #expect(entry.kind == .pdl1)
        #expect(entry.notice.contains("https://www.soumu.go.jp/denshijiti/code.html"))
        #expect(entry.notice.hasSuffix("を加工して作成"))
        let text = try #require(LicenseCatalog.text(of: entry))
        #expect(text.contains("https://www.digital.go.jp/resources/open_data/public_data_license_v1.0"))
        // 同梱の一覧の注記と同じ出典を書いている
        let url = try #require(
            Bundle.main.url(forResource: MunicipalityCatalog.resourceName, withExtension: MunicipalityCatalog.resourceExtension)
        )
        let tsv = try String(contentsOf: url, encoding: .utf8)
        #expect(tsv.contains(entry.notice))
    }

    /// 全文にメールアドレスを入れていない（public リポジトリとアプリの画面に出さない）
    @Test(arguments: LicenseCatalog.all)
    func licenseTextHasNoEmailAddress(entry: LicenseEntry) throws {
        let text = try #require(LicenseCatalog.text(of: entry))
        #expect(!text.contains("@"))
        #expect(!text.contains(" at nanopb"))
    }

    /// 全文は空の行で段落に分け、段落の中の折り返しと字下げを詰める（PR #100 の持ち越し）
    @Test
    func paragraphsJoinWrappedLines() {
        let text = "\n   Title\n  Version 1\n\n   1. First line\n      continues here.\n\n\nLast\n"
        #expect(LicenseCatalog.paragraphs(of: text) == ["Title Version 1", "1. First line continues here.", "Last"])
        #expect(LicenseCatalog.paragraphs(of: "").isEmpty)
    }

    /// 同梱の全文を段落に分けても、文字（空白を除く）は欠けない
    @Test(arguments: LicenseCatalog.all)
    func paragraphsKeepAllText(entry: LicenseEntry) throws {
        let text = try #require(LicenseCatalog.text(of: entry))
        let paragraphs = LicenseCatalog.paragraphs(of: text)
        #expect(paragraphs.count > 1)
        let letters = { (value: String) in value.filter { !$0.isWhitespace } }
        #expect(letters(paragraphs.joined()) == letters(text))
    }
}
