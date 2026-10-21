//
//  NameValidationTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// 名前（表示名・ルーム名）の検証を確かめる。
///
/// TypeScript 側の `backend/functions/src/domain/text.test.ts`・`validation.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct NameValidationTests {
    /// backend の Jest と同じ範囲（1〜10 文字）
    static let range = 1...10

    // MARK: 文字数（text.test.ts の characters）

    /// 書記素クラスタで数える（`Intl.Segmenter` と同じ）
    @Test
    func countsGraphemeClusters() {
        #expect("ゆい".count == 2)
        #expect("👨‍👩‍👧".count == 1)
        #expect("が".count == 1)
        #expect("\r\n".count == 1)
    }

    // MARK: 空白（text.test.ts）

    /// U+0085 と U+FEFF をどちらも空白とみなす（一覧は 26 個）
    @Test
    func whitespacesIncludeNextLineAndByteOrderMark() {
        #expect(NameValidation.whitespaces.contains("\u{0085}"))
        #expect(NameValidation.whitespaces.contains("\u{FEFF}"))
        #expect(!NameValidation.whitespaces.contains("A"))
        #expect(NameValidation.whitespaces.count == 26)
    }

    @Test(arguments: [
        ("  ゆい　", "ゆい"),
        ("\u{0085}ゆ い\u{FEFF}", "ゆ い"),
        (" \u{3000} ", ""),
        ("", "")
    ])
    func trimsOnlyLeadingAndTrailingWhitespace(text: String, expected: String) {
        #expect(NameValidation.trimWhitespace(text) == expected)
    }

    // MARK: 名前に入れられない文字（text.test.ts）

    /// 制御文字・改行・タブ・行と段落の区切りを含むと true
    @Test(arguments: ["ゆ\nい", "ゆ\r\nい", "ゆ\tい", "ゆ\u{0000}い", "ゆ\u{0085}い", "ゆ\u{007F}い", "ゆ\u{2028}い", "ゆ\u{2029}い"])
    func detectsForbiddenCharacters(text: String) {
        #expect(NameValidation.containsForbiddenCharacter(text))
    }

    /// ふつうの文字・間の空白・絵文字は false
    @Test(arguments: ["ゆい", "ゆ い", "ゆ　い", "👨‍👩‍👧", "❤️"])
    func allowsOrdinaryCharacters(text: String) {
        #expect(!NameValidation.containsForbiddenCharacter(text))
    }

    // MARK: 見えない文字だけか（text.test.ts）

    /// 書式文字・既定で表示しない文字（U+3164・異体字セレクタ）・空白だけなら true
    @Test(arguments: [
        "", "\u{200B}", "\u{200C}\u{200D}", "\u{2060}", "\u{FEFF}", "\u{3164}", "\u{200B} \u{200B}", "\u{00AD}", "\u{FE0F}"
    ])
    func detectsInvisibleOnly(text: String) {
        #expect(NameValidation.isInvisibleOnly(text))
    }

    /// 見える文字が 1 つでもあれば false（ZWJ でつないだ絵文字・異体字セレクタ付き・結合文字も見える）
    @Test(arguments: ["ゆ", "\u{200B}ゆ", "👨‍👩‍👧", "❤️", "a\u{0301}"])
    func visibleCharacterIsNotInvisibleOnly(text: String) {
        #expect(!NameValidation.isInvisibleOnly(text))
    }

    // MARK: 名前の検証（validation.test.ts の requireTrimmedText）

    /// 前後の空白を取り除いて、書記素クラスタで数える
    @Test(arguments: [
        ("  ゆい　", "ゆい"),
        ("あいうえおかきくけこ", "あいうえおかきくけこ"),
        (String(repeating: "👨‍👩‍👧", count: 10), String(repeating: "👨‍👩‍👧", count: 10))
    ])
    func acceptsTrimmedNameInRange(text: String, expected: String) {
        #expect(NameValidation.validated(text, length: Self.range) == expected)
    }

    /// 範囲の外・空白だけは受け付けない
    @Test(arguments: ["", " \u{3000}\u{0085}\u{FEFF} ", "あいうえおかきくけこさ"])
    func rejectsOutOfRangeOrBlank(text: String) {
        #expect(NameValidation.validated(text, length: Self.range) == nil)
    }

    /// 途中に制御文字・改行・タブ・行区切りを含む名前は受け付けない（前後の改行・タブは空白として取り除く）
    @Test(arguments: ["ゆ\nい", "ゆ\tい", "ゆ\u{0000}い", "ゆ\u{0085}い", "ゆ\u{2028}い"])
    func rejectsForbiddenCharacters(text: String) {
        #expect(NameValidation.validated(text, length: Self.range) == nil)
    }

    @Test
    func trimsLeadingAndTrailingNewlines() {
        #expect(NameValidation.validated("\n\tゆい\r\n", length: Self.range) == "ゆい")
    }

    /// 見えない文字と空白だけの名前は空とみなして受け付けない
    @Test(arguments: ["\u{200B}", " \u{200B}\u{200D} ", "\u{2060}\u{FEFF}", "\u{3164}", "\u{200B} \u{200B}", "\u{FE0F}"])
    func rejectsInvisibleOnly(text: String) {
        #expect(NameValidation.validated(text, length: Self.range) == nil)
    }

    /// 見える文字があれば、見えない文字を含んでいても受け付ける（取り除かない）
    @Test
    func keepsInvisibleCharactersBetweenVisibleOnes() {
        #expect(NameValidation.validated("ゆ\u{200B}い", length: Self.range) == "ゆ\u{200B}い")
    }

    /// 書記素の数が範囲内でも、UTF-16 の長さが上限（書記素の上限 × 16）を超えたら受け付けない
    @Test
    func rejectsTooManyUTF16Units() {
        let limit = Self.range.upperBound * NameValidation.maxUTF16UnitsPerCharacter
        #expect(limit == 160)
        // 結合文字（U+0301）を大量につないだ 1 文字
        #expect(NameValidation.validated("a" + String(repeating: "\u{0301}", count: 50_000), length: Self.range) == nil)
        let atLimit = "a" + String(repeating: "\u{0301}", count: limit - 1)
        #expect(atLimit.count == 1)
        #expect(NameValidation.validated(atLimit, length: Self.range) == atLimit)
        #expect(NameValidation.validated(atLimit + "\u{0301}", length: Self.range) == nil)
        // 前後の空白は取り除いてから数える
        #expect(NameValidation.validated("  \(atLimit)  ", length: Self.range) == atLimit)
    }

    /// 最も長い絵文字でも上限の文字数まで入れられる
    @Test(arguments: ["👩🏻‍❤️‍💋‍👨🏼", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "👨‍👩‍👧‍👦"])
    func acceptsLongestEmojiUpToLimit(emoji: String) {
        let name = String(repeating: emoji, count: Self.range.upperBound)
        #expect(name.count == Self.range.upperBound)
        #expect(NameValidation.validated(name, length: Self.range) == name)
    }

    /// 表示名（10 文字）とルーム名（20 文字）の UTF-16 の上限
    @Test
    func utf16LimitsForDisplayNameAndRoomName() {
        #expect(DomainConstants.Limits.displayNameLength.upperBound * NameValidation.maxUTF16UnitsPerCharacter == 160)
        #expect(DomainConstants.Limits.roomNameLength.upperBound * NameValidation.maxUTF16UnitsPerCharacter == 320)
    }
}
