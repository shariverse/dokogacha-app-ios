/**
 * 文字列の扱い（文字数の数え方・空白）を、ドメインのロジックでそろえるための道具。
 * Swift 側は `String` の `count`（書記素クラスタ）と、`InviteCode.ignoredWhitespaces` の一覧に当たる。
 */

/**
 * 空白とみなす文字（Unicode のコードポイント）。
 * Unicode の White_Space（Swift の `Character.isWhitespace`）と、JavaScript の `\s` の両方が空白とみなす文字の和
 * （`U+0085` は White_Space だけ、`U+FEFF` は `\s` だけが空白とみなす）。
 * 言語ごとの空白の定義の違いで結果が変わらないよう、一覧を明示する。
 * Swift 側の `InviteCode.ignoredWhitespaces` と同じ一覧。片方を変えたら両方を変える。
 */
export const WHITESPACE_CODE_POINTS: readonly number[] = [
  0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x0085, 0x00a0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
  0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
];

/** 空白のコードポイントの集合 */
const WHITESPACE_SET: ReadonlySet<number> = new Set(WHITESPACE_CODE_POINTS);

/** 文字（書記素クラスタ）に分ける道具。Swift の `Character` と同じ単位で数える */
const graphemeSegmenter = new Intl.Segmenter("ja", { granularity: "grapheme" });

/**
 * 文字列を文字（書記素クラスタ）の一覧にする。
 * Swift 側は `String` の `count`・`prefix` が書記素クラスタで数えるので、文字数の判定と切り詰めをそろえるために使う。
 * @param text 分ける文字列
 * @returns 文字の一覧
 */
export function characters(text: string): string[] {
  return Array.from(graphemeSegmenter.segment(text), (segment) => segment.segment);
}

/**
 * コードポイントが空白（`WHITESPACE_CODE_POINTS`）か。
 * @param codePoint 調べるコードポイント
 * @returns 空白なら true
 */
export function isWhitespaceCodePoint(codePoint: number): boolean {
  return WHITESPACE_SET.has(codePoint);
}

/**
 * 前後の空白（`WHITESPACE_CODE_POINTS`）を取り除く。間の空白は残す。
 * `String.prototype.trim` は `U+0085` を空白とみなさないので使わない。
 * @param text 取り除く前の文字列
 * @returns 前後の空白を取り除いた文字列
 */
export function trimWhitespace(text: string): string {
  const points = Array.from(text);
  let start = 0;
  let end = points.length;
  while (start < end && isWhitespaceCodePoint(points[start]?.codePointAt(0) ?? -1)) {
    start += 1;
  }
  while (end > start && isWhitespaceCodePoint(points[end - 1]?.codePointAt(0) ?? -1)) {
    end -= 1;
  }
  return points.slice(start, end).join("");
}
