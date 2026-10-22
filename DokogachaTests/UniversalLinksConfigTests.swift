//
//  UniversalLinksConfigTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// Universal Links の設定（xcconfig のドメイン・entitlements・Hosting の apple-app-site-association）が、
/// アプリの招待リンクの定数（`DomainConstants.Web`）と食い違っていないことを確かめる（タスク 34）。
///
/// どれもリポジトリのファイルを `#filePath` から読む（テストのバンドルに複製しない。`DesignTokensTests` と同じ）。
/// Simulator では Universal Links でアプリを開けないので、設定の食い違いはここで見つける
struct UniversalLinksConfigTests {
    /// リポジトリの直下（このファイルは `DokogachaTests/` の直下にある）
    nonisolated static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// `Configs/Project.xcconfig` の `名前 = 値` の行を辞書にする（コメントの行は読まない）
    static func projectSettings() throws -> [String: String] {
        let text = try String(contentsOf: repositoryRoot.appending(path: "Configs/Project.xcconfig"), encoding: .utf8)
        var settings: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("//") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                settings[parts[0]] = parts[1]
            }
        }
        return settings
    }

    /// xcconfig のドメインは、招待リンクのドメインと同じ
    @Test
    func xcconfigDomainMatchesInviteLink() throws {
        let settings = try Self.projectSettings()
        #expect(settings["DG_WEB_DOMAIN"] == DomainConstants.Web.domain)
        #expect(settings["CODE_SIGN_ENTITLEMENTS"] == "$(DG_CODE_SIGN_ENTITLEMENTS_$(PRODUCT_TYPE:identifier))")
        #expect(settings["DG_CODE_SIGN_ENTITLEMENTS_com_apple_product_type_application"] == "Configs/Dokogacha.entitlements")
    }

    /// entitlements の Associated Domains は、xcconfig のドメインの `applinks:`
    @Test
    func entitlementsDeclareApplinks() throws {
        let data = try Data(contentsOf: Self.repositoryRoot.appending(path: "Configs/Dokogacha.entitlements"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let domains = try #require(plist["com.apple.developer.associated-domains"] as? [String])
        #expect(domains == ["applinks:$(DG_WEB_DOMAIN)"])
    }

    /// Hosting の apple-app-site-association は、Team ID と Bundle ID のアプリに、招待リンクのパスを渡す
    @Test
    func appSiteAssociationMatchesApp() throws {
        let settings = try Self.projectSettings()
        let teamID = try #require(settings["DEVELOPMENT_TEAM"])
        let bundleID = try #require(settings["APP_BUNDLE_IDENTIFIER"])
        let url = Self.repositoryRoot.appending(path: "backend/hosting/public/.well-known/apple-app-site-association")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let applinks = try #require(json["applinks"] as? [String: Any])
        let details = try #require(applinks["details"] as? [[String: Any]])
        #expect(details.count == 1)
        let detail = try #require(details.first)
        #expect(detail["appIDs"] as? [String] == ["\(teamID).\(bundleID)"])
        let components = try #require(detail["components"] as? [[String: Any]])
        #expect(components.compactMap { $0["/"] as? String } == [DomainConstants.Web.inviteLinkPathPrefix + "*"])
    }
}
