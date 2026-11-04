//
//  UniversalLinksConfigTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// Universal Links の設定（xcconfig のドメイン・entitlements・Bundle ID）が、アプリの招待リンクの定数（`DomainConstants.Web`）と、
/// 手順書（`docs/setup-human.md` の 10）に載せた apple-app-site-association と食い違っていないことを確かめる（タスク 34）。
///
/// AASA と招待リンクのランディングページは運営者のサイト（shilokuma-inc/shilokuma-web）が配信し、このリポジトリには無い（Issue #206）。
/// 手順書の AASA を shilokuma-web に置く中身の正にして、ここでアプリの設定と突き合わせる。
/// どれもリポジトリのファイルを `#filePath` から読む（テストのバンドルに複製しない。`DesignTokensTests` と同じ）。
/// Simulator では Universal Links でアプリを開けないので、設定の食い違いはここで見つける
struct UniversalLinksConfigTests {
    /// リポジトリの直下（このファイルは `DokogachaTests/` の直下にある）
    nonisolated static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// `Configs/Project.xcconfig` の `名前 = 値` の行を辞書にする（コメントの行は読まない）
    static func projectSettings() throws -> [String: String] {
        try xcconfigSettings(named: "Project")
    }

    /// `Configs/<名前>.xcconfig` の `名前 = 値` の行を辞書にする（コメントと `#include` の行は読まない。読み込んだ側の値は入らない）
    static func xcconfigSettings(named name: String) throws -> [String: String] {
        let text = try String(contentsOf: repositoryRoot.appending(path: "Configs/\(name).xcconfig"), encoding: .utf8)
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

    /// Stg（TestFlight）と Debug は、本番の Bundle ID に `.stg`・`.dev` を付けた別のアプリ（Issue #189・#210）。Release は本番の Bundle ID のまま
    @Test
    func stgAndDebugUseSeparateBundleIDs() throws {
        let bundleID = try #require(try Self.projectSettings()["APP_BUNDLE_IDENTIFIER"])
        #expect(bundleID == "jp.shilokuma.Dokogacha")
        #expect(try Self.xcconfigSettings(named: "Stg")["APP_BUNDLE_IDENTIFIER"] == bundleID + ".stg")
        #expect(try Self.xcconfigSettings(named: "Debug")["APP_BUNDLE_IDENTIFIER"] == bundleID + ".dev")
        #expect(try Self.xcconfigSettings(named: "Release")["APP_BUNDLE_IDENTIFIER"] == nil)
    }

    /// テストのホストのアプリ（Debug）は、Debug の Bundle ID でビルドされている
    @Test
    func hostAppUsesDebugBundleID() throws {
        let debugBundleID = try #require(try Self.xcconfigSettings(named: "Debug")["APP_BUNDLE_IDENTIFIER"])
        #expect(Bundle.main.bundleIdentifier == debugBundleID)
    }

    /// 手順書の apple-app-site-association は、Team ID と Bundle ID のアプリ（本番・Stg の順）に、招待リンクのパスだけを渡す
    @Test
    func documentedAppSiteAssociationMatchesApp() throws {
        let settings = try Self.projectSettings()
        let teamID = try #require(settings["DEVELOPMENT_TEAM"])
        let bundleID = try #require(settings["APP_BUNDLE_IDENTIFIER"])
        let stgBundleID = try #require(try Self.xcconfigSettings(named: "Stg")["APP_BUNDLE_IDENTIFIER"])
        let data = try #require(try Self.documentedAppSiteAssociation().data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let applinks = try #require(json["applinks"] as? [String: Any])
        let details = try #require(applinks["details"] as? [[String: Any]])
        #expect(details.count == 1)
        let detail = try #require(details.first)
        #expect(detail["appIDs"] as? [String] == ["\(teamID).\(bundleID)", "\(teamID).\(stgBundleID)"])
        let components = try #require(detail["components"] as? [[String: Any]])
        #expect(components.compactMap { $0["/"] as? String } == [DomainConstants.Web.inviteLinkPathPrefix + "*"])
    }

    /// 手順書（`docs/setup-human.md`）の JSON のコードブロックのうち、`applinks` を持つもの（1 つだけ置く）。リストの中で字下げしたブロックも読む
    static func documentedAppSiteAssociation() throws -> String {
        let blocks = try String(contentsOf: repositoryRoot.appending(path: "docs/setup-human.md"), encoding: .utf8)
            .matches(of: /```json\n([\s\S]*?)\n[ ]*```/)
            .map { String($0.output.1) }
            .filter { $0.contains("\"applinks\"") }
        try #require(blocks.count == 1)
        return try #require(blocks.first)
    }
}
