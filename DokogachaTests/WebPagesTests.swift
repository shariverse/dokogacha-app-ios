//
//  WebPagesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// アプリと App Store の掲載情報が開く Web のページ（利用規約・プライバシーポリシー・サポート。`DomainConstants.Web`）の URL を確かめる。
///
/// ページは運営者のサイト（shilokuma-inc/shilokuma-web）が配信し、このリポジトリには無い（Issue #206）。
/// 開けるかは shilokuma-web 側と `docs/setup-human.md` の 11 の「確かめ方」で確かめる
struct WebPagesTests {
    /// アプリと App Store の掲載情報が開くページの URL
    nonisolated static let pageURLs = [
        DomainConstants.Web.termsURL,
        DomainConstants.Web.privacyPolicyURL,
        DomainConstants.Web.supportURL
    ]

    /// shilokuma-web で決めた URL（末尾のスラッシュまで同じ）
    @Test
    func urlsMatchOperatorSite() {
        #expect(DomainConstants.Web.operatorSiteDomain == "shilokuma.jp")
        #expect(DomainConstants.Web.termsURL == "https://shilokuma.jp/terms/dokogacha/")
        #expect(DomainConstants.Web.privacyPolicyURL == "https://shilokuma.jp/privacy/dokogacha/")
        #expect(DomainConstants.Web.supportURL == "https://shilokuma.jp/about/")
    }

    /// どのページも運営者のサイトの https で、招待リンクのドメインには置かない。パスはスラッシュで終わるディレクトリの形
    @Test(arguments: pageURLs)
    func pageIsOnOperatorSite(urlString: String) throws {
        let components = try #require(URLComponents(string: urlString))
        #expect(components.scheme == DomainConstants.Web.scheme)
        #expect(components.host == DomainConstants.Web.operatorSiteDomain)
        #expect(components.host != DomainConstants.Web.domain)
        #expect(components.query == nil && components.fragment == nil)
        #expect(components.path.hasPrefix("/") && components.path.hasSuffix("/"))
    }
}
