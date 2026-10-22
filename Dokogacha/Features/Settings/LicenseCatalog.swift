//
//  LicenseCatalog.swift
//  Dokogacha
//

import Foundation

/// ライセンスの種類と、全文のファイル（アプリに同梱した `.txt`）。
nonisolated enum LicenseKind: String, CaseIterable, Sendable {
    /// SIL Open Font License 1.1（同梱のフォント。04 の §2「設定画面のライセンスに OFL の表記を入れる」）
    case ofl
    /// Apache License 2.0（Firebase・Google Mobile Ads と、それが使う Google のライブラリ）
    case apache2
    /// BSD 3-Clause License（LevelDB。Firestore のキャッシュ）
    case bsd3
    /// zlib License（nanopb。Firebase が使う）
    case zlib

    /// 画面に出すライセンスの名前
    var title: String {
        switch self {
        case .ofl: "SIL Open Font License 1.1"
        case .apache2: "Apache License 2.0"
        case .bsd3: "BSD 3-Clause License"
        case .zlib: "zlib License"
        }
    }
}

/// ライセンスを表示するもの 1 つ（フォント・ライブラリ）
nonisolated struct LicenseEntry: Identifiable, Hashable, Sendable {
    /// 画面とテストで使う ID
    let id: String
    /// 名前
    let name: String
    /// 著作権の表示
    let notice: String
    /// ライセンスの種類
    let kind: LicenseKind
    /// 全文のファイルの名前（拡張子 `.txt` を除く。アプリのバンドルの直下に入る）
    let textResource: String
}

/// S-15 のライセンスの画面に出す一覧（同梱のフォントと、アプリに入る主要なライブラリ）。
///
/// ライブラリは SPM で入れたもの（firebase-ios-sdk・Google Mobile Ads）と、それらがアプリに持ち込むもの（`Package.resolved` にあるもの）。
/// ビルドのときだけ使うもの（SwiftLint）は入れない。依存を足したら、ここと `Dokogacha/Resources/Licenses/` に足す
nonisolated enum LicenseCatalog {
    /// 同梱のフォント（`Dokogacha/Resources/Fonts/` の OFL の全文）
    static let fonts: [LicenseEntry] = [
        LicenseEntry(
            id: "mochiy-pop-one",
            name: "Mochiy Pop One",
            notice: "Copyright 2020 The Mochiypop Project Authors (https://github.com/fontdasu/Mochiypop)",
            kind: .ofl,
            textResource: "MochiyPopOne-OFL"
        ),
        LicenseEntry(
            id: "zen-maru-gothic",
            name: "Zen Maru Gothic",
            notice: "Copyright 2021 The Zen Maru Gothic Project Authors (https://github.com/googlefonts/zen-marugothic)",
            kind: .ofl,
            textResource: "ZenMaruGothic-OFL"
        )
    ]

    /// アプリに入るライブラリ
    static let libraries: [LicenseEntry] = [
        google("firebase-ios-sdk", name: "Firebase Apple SDK"),
        google("google-mobile-ads", name: "Google Mobile Ads SDK"),
        google("google-user-messaging-platform", name: "Google User Messaging Platform SDK"),
        google("google-app-measurement", name: "Google App Measurement"),
        google("google-ads-on-device-conversion", name: "Google Ads On-Device Conversion SDK"),
        google("app-check", name: "App Check"),
        google("google-utilities", name: "GoogleUtilities"),
        google("google-data-transport", name: "GoogleDataTransport"),
        google("gtm-session-fetcher", name: "GTMSessionFetcher"),
        google("promises", name: "Promises"),
        google("interop-ios-for-google-sdks", name: "Interop for Google SDKs"),
        LicenseEntry(id: "grpc", name: "gRPC", notice: "Copyright The gRPC Authors", kind: .apache2, textResource: apacheResource),
        LicenseEntry(id: "abseil", name: "Abseil", notice: "Copyright The Abseil Authors", kind: .apache2, textResource: apacheResource),
        LicenseEntry(
            id: "leveldb",
            name: "LevelDB",
            notice: "Copyright (c) 2011 The LevelDB Authors. All rights reserved.",
            kind: .bsd3,
            textResource: "LevelDB-BSD-3-Clause"
        ),
        LicenseEntry(id: "nanopb", name: "nanopb", notice: "Copyright (c) 2011 Petteri Aimonen", kind: .zlib, textResource: "nanopb-Zlib")
    ]

    /// フォントとライブラリのすべて
    static var all: [LicenseEntry] {
        fonts + libraries
    }

    /// Apache License 2.0 の全文のファイル
    private static let apacheResource = "Apache-2.0"

    /// Google の Apache License 2.0 のライブラリ
    private static func google(_ id: String, name: String) -> LicenseEntry {
        LicenseEntry(id: id, name: name, notice: "Copyright Google LLC", kind: .apache2, textResource: apacheResource)
    }

    /// ライセンスの全文（アプリのバンドルから読む。読めなければ nil）
    static func text(of entry: LicenseEntry, in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: entry.textResource, withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
