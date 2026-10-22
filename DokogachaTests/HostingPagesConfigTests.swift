//
//  HostingPagesConfigTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// アプリが開く Web のページ（利用規約・プライバシーポリシー。`DomainConstants.Web`）が、
/// Hosting で配信するファイル（`backend/hosting/public/`）と `firebase.json` の設定で開けることを確かめる（タスク 35）。
///
/// どれもリポジトリのファイルを `#filePath` から読む（テストのバンドルに複製しない。`UniversalLinksConfigTests` と同じ）。
/// 実際に配信して 200 で返るかは、backend の Emulator のテスト（`backend/test/emulator/hosting.test.ts`）で確かめる
struct HostingPagesConfigTests {
    /// リポジトリの直下（このファイルは `DokogachaTests/` の直下にある）
    nonisolated static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// アプリが開く Hosting のページの URL
    nonisolated static let pageURLs = [DomainConstants.Web.termsURL, DomainConstants.Web.privacyPolicyURL]

    /// URL は Web のドメインの https で、パスに対応する HTML が Hosting の公開ディレクトリにある
    @Test(arguments: pageURLs)
    func pageIsServedByHosting(urlString: String) throws {
        let components = try #require(URLComponents(string: urlString))
        #expect(components.scheme == DomainConstants.Web.scheme)
        #expect(components.host == DomainConstants.Web.domain)
        #expect(components.query == nil)
        let path = components.path
        #expect(path.hasPrefix("/") && !path.hasSuffix("/") && !path.hasSuffix(".html"))
        let file = Self.repositoryRoot.appending(path: "backend/hosting/public\(path).html")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    /// 拡張子なしの URL で HTML を開くには、Hosting の `cleanUrls` が要る
    @Test
    func hostingUsesCleanURLs() throws {
        let data = try Data(contentsOf: Self.repositoryRoot.appending(path: "backend/firebase.json"))
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hosting = try #require(config["hosting"] as? [String: Any])
        #expect(hosting["cleanUrls"] as? Bool == true)
    }
}
