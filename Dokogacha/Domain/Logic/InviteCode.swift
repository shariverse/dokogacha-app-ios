//
//  InviteCode.swift
//  Dokogacha
//
//  招待コード（02 の §2.4・F-04）の生成・表示・入力の正規化・検証。
//  TypeScript 側の `backend/functions/src/domain/inviteCode.ts` と同じ規則で、06 の §2 の同じケースを両方で確かめる。
//

import Foundation

/// 招待コード（英大文字と数字の 6 文字。紛らわしい `0 O 1 I` は使わない）。
///
/// 値（`value`）はハイフンなしの 6 文字で、Firestore の `rooms.inviteCode`・`inviteCodes/{code}` に保存する形。
/// 表示は 3 文字ずつハイフンで区切る（`DK7-29Q`）。この型の値は、必ず使える文字だけの 6 文字になっている。
nonisolated struct InviteCode: Hashable, Sendable {
    /// 使う文字（英大文字 24 文字と数字 8 文字の 32 文字）。`0 O 1 I` を除く
    static let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    /// コードの文字数
    static let length = 6
    /// 表示でハイフンを入れる位置（先頭からの文字数）
    static let groupLength = 3
    /// 表示の区切り
    static let separator: Character = "-"
    /// 入力から取り除く区切りの文字（ハイフン・ダッシュ・マイナス・長音記号）。空白は別に取り除く。
    ///
    /// 日本語の入力では、ハイフンのつもりで全角のハイフン・長音記号（ー）を打つことが多いため含める。
    static let ignoredSeparators: Set<Character> = ["-", "‐", "‑", "‒", "–", "—", "―", "−", "ー"]

    /// ハイフンなしの 6 文字（保存する形）
    let value: String

    /// 入力を正規化して、招待コードとして正しければ作る。
    ///
    /// 小文字・全角の英数字・ハイフン・空白を受け付ける（`normalize(_:)`）。
    /// 正規化したあとに 6 文字でない・使えない文字（`0 O 1 I` や記号）を含むときは nil。
    /// - Parameter input: 入力された文字列（貼り付けを含む）
    init?(_ input: String) {
        let normalized = Self.normalize(input)
        guard Self.isValid(normalized) else {
            return nil
        }
        value = normalized
    }

    /// 正規化済みで正しいと分かっている値から作る（生成のときだけ使う）
    private init(validated value: String) {
        self.value = value
    }

    /// 表示の形（`DK7-29Q`）
    var displayText: String {
        Self.formatted(value)
    }

    /// 招待コードを作る。
    ///
    /// 乱数を注入できるように、`0..<上限` の整数を返す関数を受け取る（TypeScript の `crypto.randomInt` と同じ形）。
    /// 32 文字から 1 文字ずつ、6 回選ぶ。重複の確かめと再生成は呼ぶ側（`createRoom`）で行う。
    /// - Parameter randomIndex: `0..<上限` の整数を返す乱数
    /// - Returns: 生成したコード
    static func generate(randomIndex: (Int) -> Int) -> Self {
        let characters = (0..<length).map { _ in alphabet[randomIndex(alphabet.count)] }
        return Self(validated: String(characters))
    }

    /// 乱数の生成器で招待コードを作る（既定は暗号論的に安全な `SystemRandomNumberGenerator`）。
    /// - Parameter generator: 乱数の生成器
    /// - Returns: 生成したコード
    static func generate(using generator: inout some RandomNumberGenerator) -> Self {
        generate { Int.random(in: 0..<$0, using: &generator) }
    }

    /// 入力の文字列を、招待コードの形に正規化する（検証はしない）。
    ///
    /// 1. 全角の英数字・記号・空白を半角にする（Unicode の互換分解 NFKC）
    /// 2. 空白と区切りの文字（`ignoredSeparators`）を取り除く
    /// 3. 英字を大文字にする
    /// - Parameter input: 入力された文字列
    /// - Returns: 正規化した文字列（使えない文字はそのまま残す）
    static func normalize(_ input: String) -> String {
        let characters = input.precomposedStringWithCompatibilityMapping
            .filter { !$0.isWhitespace && !ignoredSeparators.contains($0) }
        return String(characters).uppercased()
    }

    /// 正規化済みの文字列が、招待コードとして正しいか（6 文字で、すべて使える文字）。
    /// - Parameter normalized: `normalize(_:)` した文字列
    /// - Returns: 正しければ true
    static func isValid(_ normalized: String) -> Bool {
        normalized.count == length && normalized.allSatisfy(alphabet.contains)
    }

    /// 文字列を表示の形にする（先頭から 3 文字目の後ろにハイフンを入れる）。3 文字以下ならそのまま。
    ///
    /// 位置だけで区切り、使える文字かどうかは見ない（入力中の途中の文字列にも使うため）。
    /// - Parameter characters: ハイフンなしの文字列
    /// - Returns: 表示の形
    static func formatted(_ characters: String) -> String {
        guard characters.count > groupLength else {
            return characters
        }
        let splitIndex = characters.index(characters.startIndex, offsetBy: groupLength)
        return String(characters[..<splitIndex]) + String(separator) + String(characters[splitIndex...])
    }

    /// 入力欄に出す文字列（S-05「ハイフンは自動挿入、英大文字に自動変換、貼り付け対応」）。
    ///
    /// 正規化して 6 文字までに切り、表示の形にする。使えない文字は残すので、検証（`init?(_:)`）で誤りにできる。
    /// - Parameter input: 入力欄の文字列
    /// - Returns: 入力欄に出し直す文字列
    static func inputText(_ input: String) -> String {
        formatted(String(normalize(input).prefix(length)))
    }
}
