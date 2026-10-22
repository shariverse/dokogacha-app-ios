//
//  InviteCodeTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// 招待コード（06 の §2「6文字、使用文字に `0 O 1 I` を含まない、表示は `ABC-123`」）を確かめる。
///
/// TypeScript 側の `backend/functions/src/domain/inviteCode.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct InviteCodeTests {
    /// 乱数の生成器（テストで同じ並びを作るための線形合同法。値の質は問わない）
    nonisolated struct SeededGenerator: RandomNumberGenerator {
        /// 内部の状態
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    // MARK: 文字集合

    /// 使う文字は英大文字と数字の 32 文字で、`0 O 1 I` を含まない
    @Test
    func alphabetExcludesConfusingCharacters() {
        #expect(String(InviteCode.alphabet) == "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        #expect(InviteCode.alphabet.count == 32)
        #expect(Set(InviteCode.alphabet).count == 32)
        for confusing in ["0", "O", "1", "I"] as [Character] {
            #expect(!InviteCode.alphabet.contains(confusing), "\(confusing) を使っている")
        }
    }

    // MARK: 生成

    /// 注入した乱数のとおりに、文字集合から 6 文字を選ぶ
    @Test
    func generatesFromInjectedRandom() {
        #expect(InviteCode.generate { _ in 0 }.value == "AAAAAA")
        #expect(InviteCode.generate { $0 - 1 }.value == "999999")
        var next = 0
        let code = InviteCode.generate { _ in
            defer { next += 1 }
            return next
        }
        #expect(code.value == "ABCDEF")
    }

    /// 乱数で作ったコードは、どれも 6 文字で、`0 O 1 I` を含まない
    @Test
    func generatedCodesAreValid() {
        var generator = SeededGenerator(state: 20_261_022)
        for _ in 0..<1_000 {
            let code = InviteCode.generate(using: &generator)
            #expect(code.value.count == 6)
            #expect(!code.value.contains { "0O1I".contains($0) })
            #expect(InviteCode(code.value) == code)
        }
    }

    /// 乱数で作ると、文字集合のすべての文字が出る（偏って一部の文字しか使わない、という誤りを検出する）
    @Test
    func generatedCodesUseWholeAlphabet() {
        var generator = SeededGenerator(state: 7)
        let used = (0..<1_000).reduce(into: Set<Character>()) { used, _ in
            used.formUnion(InviteCode.generate(using: &generator).value)
        }
        #expect(used == Set(InviteCode.alphabet))
    }

    // MARK: 表示

    /// 表示は 3 文字ずつハイフンで区切る（02 の §2.4 の例 `ABC-123`・03 の S-04 の例 `DK7-29Q`）
    @Test
    func displayText() throws {
        #expect(InviteCode.formatted("ABC123") == "ABC-123")
        #expect(try #require(InviteCode("DK729Q")).displayText == "DK7-29Q")
    }

    // MARK: 入力の正規化と検証

    /// 正しいコードとして読める入力（小文字・ハイフン・空白・全角・長音記号）と、正規化した値
    nonisolated static let validInputs: [(String, String)] = [
        ("DK729Q", "DK729Q"),
        ("dk729q", "DK729Q"),
        ("DK7-29Q", "DK729Q"),
        (" dk7 29q ", "DK729Q"),
        ("ＤＫ７－２９Ｑ", "DK729Q"),
        ("dk7ー29q", "DK729Q"),
        ("DK7\u{3000}29Q", "DK729Q"),
        ("DK7\u{0085}29Q", "DK729Q"),
        ("\u{FEFF}DK729Q", "DK729Q"),
        ("DK7\r\n29Q", "DK729Q")
    ]

    /// 正規化すると招待コードとして読める
    @Test(arguments: Self.validInputs)
    func acceptsNormalizedInput(input: String, expected: String) throws {
        #expect(InviteCode.normalize(input) == expected)
        #expect(try #require(InviteCode(input)).value == expected)
    }

    /// 招待コードとして読めない入力（文字数が違う・`0 O 1 I`・記号・空）
    @Test(arguments: ["", "DK729", "DK729QA", "DK729O", "DK7290", "DK7291", "DK729I", "DK7_29Q", "ABC123"])
    func rejectsInvalidInput(input: String) {
        #expect(InviteCode(input) == nil)
        #expect(!InviteCode.isValid(InviteCode.normalize(input)))
    }

    /// 取り除く文字の一覧は TypeScript 側と同じ（空白 26 文字・区切り 9 文字）
    @Test
    func ignoredCharactersMatchTypeScript() {
        let whitespaces = InviteCode.ignoredWhitespaces.map { String($0.value, radix: 16) }
        #expect(whitespaces == [
            "9", "a", "b", "c", "d", "20", "85", "a0", "1680", "2000", "2001", "2002", "2003", "2004",
            "2005", "2006", "2007", "2008", "2009", "200a", "2028", "2029", "202f", "205f", "3000", "feff"
        ])
        let separators = InviteCode.ignoredSeparators.map { String($0.value, radix: 16) }
        #expect(separators == ["2d", "2010", "2011", "2012", "2013", "2014", "2015", "2212", "30fc"])
    }

    /// 一覧のどの文字も、コードの間に入れると取り除かれる
    @Test
    func removesEveryIgnoredCharacter() {
        for scalar in InviteCode.ignoredWhitespaces + InviteCode.ignoredSeparators {
            #expect(InviteCode("DK7\(Character(scalar))29Q")?.value == "DK729Q", "U+\(String(scalar.value, radix: 16)) が残る")
        }
    }

    /// 入力欄は、大文字にしてハイフンを自動で入れ、6 文字までに切る（S-05）
    @Test
    func inputText() {
        #expect(InviteCode.inputText("").isEmpty)
        #expect(InviteCode.inputText("dk7") == "DK7")
        #expect(InviteCode.inputText("dk72") == "DK7-2")
        #expect(InviteCode.inputText("DK7-") == "DK7")
        #expect(InviteCode.inputText("dk7-29q") == "DK7-29Q")
        #expect(InviteCode.inputText("dk729q88") == "DK7-29Q")
    }

    /// ハイフンの直後で削除キーを押す（ハイフンだけが消える）と、ハイフンの前の 1 文字を消す（PR #49 の持ち越し）
    @Test
    func deletingSeparatorRemovesPreviousCharacter() {
        #expect(InviteCode.inputText("DK729Q", previous: "DK7-29Q") == "DK2-9Q")
        #expect(InviteCode.inputText("DK72", previous: "DK7-2") == "DK2")
        // ハイフンの後ろの文字を消したとき・末尾から消したときは、そのまま
        #expect(InviteCode.inputText("DK7-9Q", previous: "DK7-29Q") == "DK7-9Q")
        #expect(InviteCode.inputText("DK7-29", previous: "DK7-29Q") == "DK7-29")
        #expect(InviteCode.inputText("DK7-", previous: "DK7-2") == "DK7")
        // 打ち足し・貼り付けは今までどおり
        #expect(InviteCode.inputText("DK7-29Qx", previous: "DK7-29Q") == "DK7-29Q")
        #expect(InviteCode.inputText("dk7", previous: "DK") == "DK7")
        #expect(InviteCode.inputText("abc123", previous: "") == "ABC-123")
    }
}
