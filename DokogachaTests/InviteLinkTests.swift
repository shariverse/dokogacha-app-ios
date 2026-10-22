//
//  InviteLinkTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 招待リンク（02 の §2.4「`https://dokogacha.app/r/{招待コード}`」）の組み立てと、Universal Links で開かれた URL の読み取りを確かめる
struct InviteLinkTests {
    /// ハイフンなしのコードを `/r/` の後ろに入れる
    @Test
    func buildsLinkWithCodeWithoutHyphen() throws {
        let code = try #require(InviteCode("DK7-29Q"))
        #expect(InviteLink.url(for: code).absoluteString == "https://dokogacha.app/r/DK729Q")
    }

    /// 小文字・全角で入力したコードでも、正規化した形でリンクにする
    @Test
    func normalizesCode() throws {
        let code = try #require(InviteCode("ｄｋ７２９ｑ"))
        #expect(InviteLink.url(for: code).absoluteString == "https://dokogacha.app/r/DK729Q")
    }

    // MARK: 開かれた URL からコードを取り出す（タスク 34）

    /// 招待コードを取り出せる URL（URL・取り出すコード）
    nonisolated static let acceptedLinks: [(url: String, code: String)] = [
        ("https://dokogacha.app/r/QW58RT", "QW58RT"),
        // 小文字・ハイフン付き・全角（パーセントエンコード）でも、InviteCode の正規化で読める
        ("https://dokogacha.app/r/qw58rt", "QW58RT"),
        ("https://dokogacha.app/r/QW5-8RT", "QW58RT"),
        ("https://dokogacha.app/r/%EF%BD%91%EF%BD%975-8RT", "QW58RT"),
        // 末尾のスラッシュは 1 つまで
        ("https://dokogacha.app/r/QW58RT/", "QW58RT"),
        // クエリ・フラグメントは見ない（共有先のアプリが付ける計測用のパラメータ）
        ("https://dokogacha.app/r/QW58RT?utm_source=line", "QW58RT"),
        ("https://dokogacha.app/r/QW58RT/?from=share#top", "QW58RT"),
        // スキームとホストは大文字・小文字を区別しない
        ("HTTPS://DokoGacha.App/r/QW58RT", "QW58RT")
    ]

    /// 招待リンクとして読まない URL
    nonisolated static let rejectedLinks: [String] = [
        // ホスト違い（サブドメイン・似たドメイン・ドメインの後ろに続くもの）
        "https://www.dokogacha.app/r/QW58RT",
        "https://dokogacha.example/r/QW58RT",
        "https://dokogacha.app.example.com/r/QW58RT",
        // スキーム違い（Universal Links は https だけ）
        "http://dokogacha.app/r/QW58RT",
        "dokogacha://r/QW58RT",
        // ユーザー名・ポート付き
        "https://user@dokogacha.app/r/QW58RT",
        "https://dokogacha.app:8443/r/QW58RT",
        // パス違い（前置きが違う・大文字の R・コードが無い・区切りが多い・末尾のスラッシュが 2 つ）
        "https://dokogacha.app/",
        "https://dokogacha.app/r",
        "https://dokogacha.app/r/",
        "https://dokogacha.app/room/QW58RT",
        "https://dokogacha.app/R/QW58RT",
        "https://dokogacha.app/x/r/QW58RT",
        "https://dokogacha.app/r/QW58RT/extra",
        "https://dokogacha.app/r/QW58RT//",
        "https://dokogacha.app/r/QW5/8RT",
        // 不正なコード（短い・長い・使わない文字 0 O 1 I・記号）
        "https://dokogacha.app/r/QW58R",
        "https://dokogacha.app/r/QW58RTX",
        "https://dokogacha.app/r/QW58R0",
        "https://dokogacha.app/r/OW58RT",
        "https://dokogacha.app/r/QW5%3C8R",
        "https://dokogacha.app/r/%3Cscript%3E"
    ]

    /// 招待リンクから招待コードを取り出す
    @Test(arguments: acceptedLinks)
    func readsInviteCodeFromLink(link: (url: String, code: String)) throws {
        let url = try #require(URL(string: link.url))
        #expect(InviteLink.inviteCode(from: url)?.value == link.code)
    }

    /// ホスト・スキーム・パスが違う URL、不正なコードの URL は読まない
    @Test(arguments: rejectedLinks)
    func ignoresOtherLinks(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InviteLink.inviteCode(from: url) == nil)
    }

    /// 組み立てた招待リンクは、そのまま読み戻せる
    @Test
    func roundTripsBuiltLink() throws {
        let code = try #require(InviteCode("DK7-29Q"))
        #expect(InviteLink.inviteCode(from: InviteLink.url(for: code)) == code)
    }
}
