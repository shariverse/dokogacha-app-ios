//
//  NameValidation.swift
//  Dokogacha
//
//  名前（表示名 F-01・ルーム名 F-02）の検証。
//  TypeScript 側の `backend/functions/src/domain/text.ts`・`validation.ts` の `requireTrimmedText` と同じ規則で、
//  `text.test.ts`・`validation.test.ts` と同じケースを `NameValidationTests` で確かめる。片方を変えたら両方を変える。
//

import Foundation

/// 名前（表示名・ルーム名）として受け付けるかの判定。
///
/// Callable（`saveProfile`・`createRoom`）がサーバーで同じ規則で確かめるので、入力欄（S-01・S-03）で先に同じ判定をして、
/// 送ってから「入力内容を確認してください」になるのを防ぐ。擬似のサーバーもこの判定を使う。
///
/// 規則（backend の `requireTrimmedText` の順）:
/// 0. 取り除く前の UTF-16 のコード単位の数が「書記素の上限 × `maxUTF16UnitsPerCharacter` + `maxSurroundingWhitespaceUTF16Units`」を超えたら拒否する
/// 1. 前後の空白（`whitespaces`）を取り除く。間の空白は残す
/// 2. UTF-16 のコード単位の数が「書記素の上限 × `maxUTF16UnitsPerCharacter`」を超えたら拒否する
/// 3. 制御文字（`\p{Cc}`。改行・タブ・U+0085 を含む）・行区切り（U+2028）・段落区切り（U+2029）を含めば拒否する
/// 4. 見えない文字（`\p{Cf}`・Default_Ignorable_Code_Point）と空白だけなら空とみなす
/// 5. 文字数（書記素クラスタ。`String.count`）が範囲に入るか
nonisolated enum NameValidation {
    /// 1 文字（書記素クラスタ）あたりに許す UTF-16 のコード単位の数（backend の `MAX_UTF16_UNITS_PER_CHARACTER`）。
    ///
    /// 結合文字を何万個もつないだ 1 文字を通さないため、文字数とは別に長さの上限を設ける。
    /// 16 は、絵文字で最も長い RGI の並び（肌の色付きのキスする 2 人が 15 単位、イングランドの旗が 14 単位）でも上限の文字数まで入れられる値。
    /// 表示名（10 文字）は 160 単位、ルーム名（20 文字）は 320 単位まで
    static let maxUTF16UnitsPerCharacter = 16

    /// 前後の空白を取り除く前の文字列に、本文の上限より多く許す UTF-16 のコード単位の数（backend の `MAX_SURROUNDING_WHITESPACE_UTF16_UNITS`）。
    ///
    /// 空白を取り除くにはスカラー値に分けるので、上限が無いと巨大な文字列をまるごと分けてから断ることになる。取り除く前にこの緩い上限で先に断る。
    /// 入力欄の前後に打った空白（数個〜数十個）は十分に収まる値
    static let maxSurroundingWhitespaceUTF16Units = 256

    /// 空白とみなす文字（backend の `WHITESPACE_CODE_POINTS`）。
    ///
    /// Unicode の White_Space と JavaScript の `\s` の和で、招待コードの入力で取り除く空白と同じ一覧
    /// （`InviteCode.ignoredWhitespaces`。言語ごとの空白の定義の違いで結果が変わらないよう、一覧を 1 つにする）
    static let whitespaces: Set<Unicode.Scalar> = Set(InviteCode.ignoredWhitespaces)

    /// 名前として受け付けるなら、前後の空白を取り除いた名前を返す。受け付けなければ nil（サーバーなら `invalid-argument`）
    /// - Parameters:
    ///   - text: 入力された名前
    ///   - length: 文字数（書記素クラスタ）の範囲（両端を含む）
    static func validated(_ text: String, length: ClosedRange<Int>) -> String? {
        // 空白を取り除く（スカラー値に分ける）前に、緩い上限で巨大な文字列を断る
        guard text.utf16.count <= length.upperBound * maxUTF16UnitsPerCharacter + maxSurroundingWhitespaceUTF16Units else {
            return nil
        }
        let trimmed = trimWhitespace(text)
        // 書記素に分ける前に長さを見て、巨大な文字列を分けずに断る
        guard trimmed.utf16.count <= length.upperBound * maxUTF16UnitsPerCharacter,
              !containsForbiddenCharacter(trimmed) else {
            return nil
        }
        let count = isInvisibleOnly(trimmed) ? 0 : trimmed.count
        return length.contains(count) ? trimmed : nil
    }

    /// 前後の空白（`whitespaces`）を取り除く（backend の `trimWhitespace`）。間の空白は残す。
    ///
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` は U+FEFF を空白とみなさないので、Unicode のスカラー値の単位で一覧と比べる
    static func trimWhitespace(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !whitespaces.contains($0) }),
              let last = scalars.lastIndex(where: { !whitespaces.contains($0) }) else {
            return ""
        }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }

    /// 名前に入れられない文字（制御文字・行区切り・段落区切り）を含むか（backend の `containsForbiddenNameCharacter`）。
    ///
    /// 一覧や通知で 1 行に収まらず表示が崩れるので、取り除かずに拒否する。前後の改行・タブは空白として先に取り除かれる
    static func containsForbiddenCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                true
            default:
                false
            }
        }
    }

    /// 見えない文字と空白だけでできているか（空の文字列も true。backend の `isInvisibleOnly`）。
    ///
    /// 見えない文字は書式文字（`\p{Cf}`。U+200B〜U+200D・U+2060・U+FEFF・U+00AD など）と、
    /// 既定で表示しない文字（Default_Ignorable_Code_Point。U+3164 のハングルの埋め字・異体字セレクタなど）。
    /// ゼロ幅スペースだけの名前を通さないために使う。見える文字が 1 つでもあれば、見えない文字を含んでいても false
    static func isInvisibleOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            whitespaces.contains(scalar)
                || scalar.properties.generalCategory == .format
                || scalar.properties.isDefaultIgnorableCodePoint
        }
    }
}
