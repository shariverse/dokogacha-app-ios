//
//  NameInputCheckTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 入力欄の名前の検証の結果（`NameInputCheck`。S-01・S-15 の表示名で共通）を確かめる
struct NameInputCheckTests {
    /// 表示名の文字数の範囲（02 の §1「1〜10文字」）
    private static let length = DomainConstants.Limits.displayNameLength

    /// 空・空白だけ・見えない文字だけは、送れず理由も出さない（文字数は 0）
    @Test(arguments: ["", "   ", "\u{200B}"])
    func emptyHasNoIssue(text: String) {
        let check = NameInputCheck(text, length: Self.length)
        #expect(check.validatedName == nil)
        #expect(check.characterCount == 0)
        #expect(check.issue == nil)
        #expect(check.limit == 10)
    }

    /// 前後の空白を取り除いた名前を送り、文字数は書記素で数える
    @Test
    func trimsAndCountsGraphemes() {
        let check = NameInputCheck("  👨‍👩‍👧‍👦ゆい ", length: Self.length)
        #expect(check.validatedName == "👨‍👩‍👧‍👦ゆい")
        #expect(check.characterCount == 3)
        #expect(check.issue == nil)
    }

    /// 上限を超えたら、上限を添えた理由を出す
    @Test
    func tooLong() {
        let check = NameInputCheck("12345678901", length: Self.length)
        #expect(check.validatedName == nil)
        #expect(check.characterCount == 11)
        #expect(check.issue == .tooLong(limit: 10))
    }

    /// 改行などの使えない文字は、その理由を出す
    @Test
    func forbiddenCharacter() {
        let check = NameInputCheck("ゆ\nい", length: Self.length)
        #expect(check.validatedName == nil)
        #expect(check.issue == .forbiddenCharacter)
    }
}
