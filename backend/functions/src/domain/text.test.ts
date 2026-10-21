import { characters, isWhitespaceCodePoint, trimWhitespace, WHITESPACE_CODE_POINTS } from "./text";

describe("characters", () => {
  it("書記素クラスタで数える（Swift の String.count と同じ）", () => {
    expect(characters("ゆい")).toHaveLength(2);
    expect(characters("👨‍👩‍👧")).toHaveLength(1);
    expect(characters("が")).toHaveLength(1);
    expect(characters("\r\n")).toHaveLength(1);
  });
});

describe("空白", () => {
  it("U+0085 と U+FEFF をどちらも空白とみなす", () => {
    expect(isWhitespaceCodePoint(0x0085)).toBe(true);
    expect(isWhitespaceCodePoint(0xfeff)).toBe(true);
    expect(isWhitespaceCodePoint(0x0041)).toBe(false);
    expect(WHITESPACE_CODE_POINTS).toHaveLength(26);
  });

  it("前後の空白だけを取り除く", () => {
    expect(trimWhitespace("  ゆい　")).toBe("ゆい");
    expect(trimWhitespace("\u{0085}ゆ い\u{FEFF}")).toBe("ゆ い");
    expect(trimWhitespace(" \u{3000} ")).toBe("");
    expect(trimWhitespace("")).toBe("");
  });
});
