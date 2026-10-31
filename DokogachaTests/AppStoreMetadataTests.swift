//
//  AppStoreMetadataTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// App Store の掲載情報（`AppStore/`）が、アプリの値と 06 の §5 に合っていることを確かめる（タスク 45）。
///
/// 掲載情報の JSON は App Store Connect に反映するワークフロー（手動実行）でしか使われず、アプリの値と食い違っても
/// ビルドもテストも通るので、ここで突き合わせる。どれもリポジトリのファイルを `#filePath` から読む（`HostingPagesConfigTests` と同じ）
struct AppStoreMetadataTests {
    /// `AppStore/` のディレクトリ
    nonisolated static let appStoreDirectory = HostingPagesConfigTests.repositoryRoot.appending(path: "AppStore")

    /// `AppStore/` の下の JSON を読む
    private static func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: appStoreDirectory.appending(path: path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// サポートとプライバシーポリシーの URL は、アプリの `DomainConstants.Web` と同じ
    @Test
    func urlsMatchWebConstants() throws {
        let shared = try Self.json("metadata/shared.json")
        #expect(shared["supportUrl"] as? String == DomainConstants.Web.supportURL)
        #expect(shared["privacyPolicyUrl"] as? String == DomainConstants.Web.privacyPolicyURL)
    }

    /// 名前とサブタイトルは 06 の §5（01 の §8）のとおりで、App Store Connect の上限（30 字）に収まる
    @Test
    func nameAndSubtitleMatchSpec() throws {
        let japanese = try Self.json("metadata/ja.json")
        let name = try #require(japanese["name"] as? String)
        let subtitle = try #require(japanese["subtitle"] as? String)
        #expect(name == "ドコガチャ")
        #expect(subtitle == "友達旅行・おでかけの行き先ガチャ")
        #expect(name.count <= 30 && subtitle.count <= 30)
    }

    /// App Store の日本語のアプリ名は、ホーム画面の日本語の名前（`Dokogacha/InfoPlist.xcstrings` の `ja`）と同じ（Discussion #147 の Q2）。
    ///
    /// 片方だけ変えると、App Store とホーム画面で名前が食い違うので、ビルドしたアプリの `ja.lproj` の値と突き合わせる
    @Test
    func nameMatchesJapaneseHomeScreenName() throws {
        let name = try #require(try Self.json("metadata/ja.json")["name"] as? String)
        #expect(name == (try AppDisplayNameTests.displayName(forLocalization: "ja")))
        #expect(name == AppDisplayNameTests.Expected.japanese)
    }

    /// 掲載する言語は日本語だけ（02 の §10 で多言語は対象外）。載せる言語ごとに説明文のファイルがある
    @Test
    func listsJapaneseOnly() throws {
        let entries = try #require(try Self.json("languages.json")["languages"] as? [[String: String]])
        #expect(entries.map { $0["language"] } == ["ja"])
        for entry in entries {
            let language = try #require(entry["language"])
            let file = Self.appStoreDirectory.appending(path: "metadata/\(language).json")
            #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        }
    }

    /// 撮る画面は撮影モードの scene にあり、06 の §5 の 5 画面（ルーム・ガチャ・行き先きっぷ・過去のアイデア・招待）がそろう
    @Test
    func screenshotScenesExistInDemo() throws {
        let entries = try #require(try Self.json("screenshots.json")["scenes"] as? [[String: String]])
        let scenes = entries.compactMap { $0["scene"] }
        #expect(scenes.count == entries.count)
        #expect(scenes.allSatisfy { ScreenshotDemo.Scene(rawValue: $0) != nil })
        let required: [ScreenshotDemo.Scene] = [.room, .gacha, .result, .pastIdeas, .invite]
        #expect(required.allSatisfy { scenes.contains($0.rawValue) })
    }

    /// 撮る表示サイズは、いまは iPhone だけ。
    ///
    /// iPad にも対応した（`TARGETED_DEVICE_FAMILY = 1,2`。Issue #156）が、iPad 13 inch の撮影はまだ撮影の仕組みに足していない
    /// （`docs/setup-human.md` の 12 の 6 で手で撮る）。足すときは、このテストを iPad 13 inch があることを確かめる形に変える
    @Test
    func screenshotsAreIPhoneOnly() throws {
        let displayTypes = try #require(try Self.json("screenshots.json")["displayTypes"] as? [String: Any])
        #expect(!displayTypes.isEmpty)
        #expect(displayTypes.keys.allSatisfy { $0.hasPrefix("APP_IPHONE_") })
    }
}
