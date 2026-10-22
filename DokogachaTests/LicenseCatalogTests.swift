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

    /// 全文にメールアドレスを入れていない（public リポジトリとアプリの画面に出さない）
    @Test(arguments: LicenseCatalog.all)
    func licenseTextHasNoEmailAddress(entry: LicenseEntry) throws {
        let text = try #require(LicenseCatalog.text(of: entry))
        #expect(!text.contains("@"))
        #expect(!text.contains(" at nanopb"))
    }
}
