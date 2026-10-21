//
//  NameInputCheck.swift
//  Dokogacha
//

import Foundation

/// 入力欄の名前（表示名・ルーム名）を検証した結果。送る値・数えた文字数・正しくない理由をまとめて持つ。
///
/// 規則は `NameValidation`（backend の `requireTrimmedText` と同じ）。入力欄（S-01・S-15 など）の文字数の表示と
/// エラーの文言、ボタンを押せるかを、同じ数え方でそろえるために 1 つの値の型にする。
nonisolated struct NameInputCheck: Equatable, Sendable {
    /// 入力が正しくない理由（空のときは理由を出さず、ボタンを無効にするだけ）
    enum Issue: Equatable, Sendable {
        /// 文字数が上限を超えた（値は上限）
        case tooLong(limit: Int)
        /// 改行などの使えない文字が入っている
        case forbiddenCharacter
    }

    /// 送る名前（前後の空白を取り除いたもの）。受け付けない入力なら nil
    let validatedName: String?
    /// 文字数（検証と同じ数え方。前後の空白を除き、見えない文字だけなら 0）
    let characterCount: Int
    /// 文字数の上限
    let limit: Int
    /// 正しくない理由。正しいとき・空のときは nil
    let issue: Issue?

    /// - Parameters:
    ///   - text: 入力中の文字列
    ///   - length: 文字数の範囲（`DomainConstants.Limits.displayNameLength` など）
    init(_ text: String, length: ClosedRange<Int>) {
        let validatedName = NameValidation.validated(text, length: length)
        let trimmed = NameValidation.trimWhitespace(text)
        let characterCount = NameValidation.isInvisibleOnly(trimmed) ? 0 : trimmed.count
        self.validatedName = validatedName
        self.characterCount = characterCount
        limit = length.upperBound
        if validatedName != nil || characterCount == 0 {
            issue = nil
        } else if characterCount > length.upperBound {
            issue = .tooLong(limit: length.upperBound)
        } else {
            // 上限の範囲で通らないのは、使えない文字（制御文字など）か、長すぎる結合文字のとき
            issue = .forbiddenCharacter
        }
    }
}
