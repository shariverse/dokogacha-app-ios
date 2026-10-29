//
//  AppIconConfigurationTests.swift
//  DokogachaTests
//

import Foundation
import ImageIO
import Testing

/// ビルド構成ごとのアプリアイコン（Discussion #128 の Q4・Q5）が、xcconfig とアセットカタログでそろっていることを確かめる。
///
/// アイコンセットの名前は `Configs/<構成>.xcconfig` の `DG_APP_ICON_NAME` で決まり、名前を間違えても
/// 外観の PNG が欠けても、ビルドは警告だけで通ってしまうので、ここで突き合わせる。
/// どれもリポジトリのファイルを `#filePath` から読む（`HostingPagesConfigTests` と同じ）
struct AppIconConfigurationTests {
    /// アセットカタログ
    nonisolated static let assetsDirectory = HostingPagesConfigTests.repositoryRoot.appending(path: "Dokogacha/Assets.xcassets")

    /// 構成ごとのアイコンセットの名前（Release は App Store に出すもので、`AppStore/app.json` の `appIcon` も同じセットを指す）
    nonisolated static let expectedIconNames = [
        "Debug": "AppIcon-Debug",
        "Stg": "AppIcon-Stg",
        "Release": "AppIcon"
    ]

    /// 外観ごとのファイル名（`Contents.json` の `appearances` の値。ライトは指定なし）
    nonisolated static let appearanceFiles: [String?: String] = [
        nil: "AppIcon.png",
        "dark": "AppIcon-Dark.png",
        "tinted": "AppIcon-Tinted.png"
    ]

    /// `Configs/<構成>.xcconfig` の `DG_APP_ICON_NAME`。構成の xcconfig に無ければ、include している `Project.xcconfig` の既定を使う
    static func iconName(configuration: String) throws -> String? {
        let text = try String(
            contentsOf: HostingPagesConfigTests.repositoryRoot.appending(path: "Configs/\(configuration).xcconfig"),
            encoding: .utf8
        )
        var value: String?
        for line in text.split(separator: "\n") where !line.hasPrefix("//") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "DG_APP_ICON_NAME" {
                value = parts[1]
            }
        }
        return try value ?? UniversalLinksConfigTests.projectSettings()["DG_APP_ICON_NAME"]
    }

    /// 構成ごとに、決めた名前のアイコンセットを使う
    @Test(arguments: ["Debug", "Stg", "Release"])
    func configurationUsesIconSet(configuration: String) throws {
        #expect(try Self.iconName(configuration: configuration) == Self.expectedIconNames[configuration])
    }

    /// アイコンセットごとに、ライト・ダーク・ティントの 1024×1024 の PNG がそろい、ライトにはアルファが無い（App Store の審査で拒まれる）
    @Test(arguments: ["AppIcon", "AppIcon-Debug", "AppIcon-Stg"])
    func iconSetHasAllAppearances(name: String) throws {
        let directory = Self.assetsDirectory.appending(path: "\(name).appiconset")
        let data = try Data(contentsOf: directory.appending(path: "Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: Any]])

        var files: [String?: String] = [:]
        for image in images {
            let appearance = (image["appearances"] as? [[String: String]])?.first?["value"]
            files[appearance] = image["filename"] as? String
            #expect(image["size"] as? String == "1024x1024")
            #expect(image["idiom"] as? String == "universal")
            #expect(image["platform"] as? String == "ios")
        }
        #expect(files == Self.appearanceFiles)

        for (appearance, file) in Self.appearanceFiles {
            let url = directory.appending(path: file)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(name)/\(file) がありません")
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 1024 && image.height == 1024)
            if appearance == nil {
                #expect([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "\(name) のライトにアルファがあります")
            }
        }
    }

    /// App Store のクリエイティブアセットのアイコン（`AppStore/app.json` の `appIcon`）は、Release のアイコンセットのライトの PNG
    @Test
    func appStoreIconIsReleaseLightIcon() throws {
        let url = HostingPagesConfigTests.repositoryRoot.appending(path: "AppStore/app.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let release = try #require(try Self.iconName(configuration: "Release"))
        #expect(json["appIcon"] as? String == "Dokogacha/Assets.xcassets/\(release).appiconset/AppIcon.png")
    }
}
