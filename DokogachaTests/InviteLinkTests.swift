//
//  InviteLinkTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 招待リンク（02 の §2.4「`https://dokogacha.app/r/{招待コード}`」）の形を確かめる
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
}
