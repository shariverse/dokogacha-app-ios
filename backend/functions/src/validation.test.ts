import {
  MAX_SURROUNDING_WHITESPACE_UTF16_UNITS,
  MAX_UTF16_UNITS_PER_CHARACTER,
  requireDocumentId,
  requireIntegerInRange,
  requireObject,
  requireTrimmedText,
} from "./validation";

/** 関数が invalid-argument の HttpsError を投げることを確かめる */
function expectInvalid(run: () => unknown): void {
  expect(run).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
}

describe("requireObject", () => {
  it("オブジェクトだけを受け付ける", () => {
    expect(requireObject({ a: 1 })).toEqual({ a: 1 });
    for (const value of [null, undefined, "a", 1, [], true]) {
      expectInvalid(() => requireObject(value));
    }
  });
});

describe("requireDocumentId", () => {
  it("パスを組み立てても別の場所を指せない ID だけを受け付ける", () => {
    expect(requireDocumentId("abcDEF123")).toBe("abcDEF123");
    expect(requireDocumentId("a".repeat(128))).toHaveLength(128);
    for (const value of ["", "a/b", ".", "..", "__name__", "a".repeat(129), 1, null, undefined]) {
      expectInvalid(() => requireDocumentId(value));
    }
  });
});

describe("requireTrimmedText", () => {
  const range = { min: 1, max: 10 };

  it("前後の空白を取り除いて、書記素クラスタで数える", () => {
    expect(requireTrimmedText("  ゆい　", range)).toBe("ゆい");
    expect(requireTrimmedText("あいうえおかきくけこ", range)).toBe("あいうえおかきくけこ");
    expect(requireTrimmedText("👨‍👩‍👧".repeat(10), range)).toBe("👨‍👩‍👧".repeat(10));
  });

  it("範囲の外・空白だけ・文字列でないものは受け付けない", () => {
    for (const value of ["", " \u{3000}\u{0085}\u{FEFF} ", "あいうえおかきくけこさ", 1, null, undefined, ["ゆい"]]) {
      expectInvalid(() => requireTrimmedText(value, range));
    }
  });

  it("途中に制御文字・改行・タブを含む名前は受け付けない（前後の改行・タブは空白として取り除く）", () => {
    expect(requireTrimmedText("\n\tゆい\r\n", range)).toBe("ゆい");
    for (const value of ["ゆ\nい", "ゆ\tい", "ゆ\u{0000}い", "ゆ\u{0085}い", "ゆ\u{2028}い"]) {
      expectInvalid(() => requireTrimmedText(value, range));
    }
  });

  it("見えない文字と空白だけの名前は空とみなして受け付けない", () => {
    for (const value of ["\u{200B}", " \u{200B}\u{200D} ", "\u{2060}\u{FEFF}", "\u{3164}", "\u{200B} \u{200B}", "\u{FE0F}"]) {
      expectInvalid(() => requireTrimmedText(value, range));
    }
    // 見える文字があれば、見えない文字を含んでいても受け付ける（取り除かない）
    expect(requireTrimmedText("ゆ\u{200B}い", range)).toBe("ゆ\u{200B}い");
  });

  it("書記素の数が範囲内でも、UTF-16 の長さが上限を超えたら受け付けない", () => {
    const limit = range.max * MAX_UTF16_UNITS_PER_CHARACTER;
    // 結合文字（U+0301）を大量につないだ 1 文字
    expectInvalid(() => requireTrimmedText(`a${"\u{0301}".repeat(50_000)}`, range));
    const atLimit = `a${"\u{0301}".repeat(limit - 1)}`;
    expect(requireTrimmedText(atLimit, range)).toBe(atLimit);
    expectInvalid(() => requireTrimmedText(`${atLimit}\u{0301}`, range));
    // 前後の空白は取り除いてから数える
    expect(requireTrimmedText(`  ${atLimit}  `, range)).toBe(atLimit);
  });

  it("前後の空白を取り除く前の長さが、上限 + 前後の空白のぶんを超えたら、取り除かずに受け付けない", () => {
    const looseLimit = range.max * MAX_UTF16_UNITS_PER_CHARACTER + MAX_SURROUNDING_WHITESPACE_UTF16_UNITS;
    expect(looseLimit).toBe(416);
    // 取り除けば「ゆい」になる文字列でも、取り除く前が緩い上限を超えたら断る
    const atLooseLimit = `ゆい${" ".repeat(looseLimit - 2)}`;
    expect(requireTrimmedText(atLooseLimit, range)).toBe("ゆい");
    expectInvalid(() => requireTrimmedText(`${atLooseLimit} `, range));
    expectInvalid(() => requireTrimmedText(`ゆい${" ".repeat(1_000_000)}`, range));
  });

  it("最も長い絵文字でも上限の文字数まで入れられる", () => {
    for (const emoji of ["👩🏻‍❤️‍💋‍👨🏼", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "👨‍👩‍👧‍👦"]) {
      expect(requireTrimmedText(emoji.repeat(range.max), range)).toBe(emoji.repeat(range.max));
    }
  });
});

describe("requireIntegerInRange", () => {
  it("範囲の整数だけを受け付ける", () => {
    expect(requireIntegerInRange(1, { min: 1, max: 10 })).toBe(1);
    expect(requireIntegerInRange(10, { min: 1, max: 10 })).toBe(10);
    for (const value of [0, 11, 1.5, Number.NaN, "3", null]) {
      expectInvalid(() => requireIntegerInRange(value, { min: 1, max: 10 }));
    }
  });
});
