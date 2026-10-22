import {
  characters,
  containsForbiddenNameCharacter,
  isInvisibleOnly,
  isWhitespaceCodePoint,
  trimWhitespace,
  WHITESPACE_CODE_POINTS,
} from "./text";

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

describe("名前に入れられない文字", () => {
  it("制御文字・改行・タブ・行と段落の区切りを含むと true", () => {
    for (const text of ["ゆ\nい", "ゆ\r\nい", "ゆ\tい", "ゆ\u{0000}い", "ゆ\u{0085}い", "ゆ\u{007F}い", "ゆ\u{2028}い", "ゆ\u{2029}い"]) {
      expect(containsForbiddenNameCharacter(text)).toBe(true);
    }
  });

  it("ふつうの文字・間の空白・絵文字は false", () => {
    for (const text of ["ゆい", "ゆ い", "ゆ　い", "👨‍👩‍👧", "❤️"]) {
      expect(containsForbiddenNameCharacter(text)).toBe(false);
    }
  });
});

describe("見えない文字だけか", () => {
  it("書式文字・既定で表示しない文字（U+3164・異体字セレクタ）・空白だけなら true", () => {
    for (const text of [
      "",
      "\u{200B}",
      "\u{200C}\u{200D}",
      "\u{2060}",
      "\u{FEFF}",
      "\u{3164}",
      "\u{200B} \u{200B}",
      "\u{00AD}",
      "\u{FE0F}",
    ]) {
      expect(isInvisibleOnly(text)).toBe(true);
    }
  });

  it("見える文字が 1 つでもあれば false（ZWJ でつないだ絵文字・異体字セレクタ付きも見える）", () => {
    for (const text of ["ゆ", "\u{200B}ゆ", "👨‍👩‍👧", "❤️", "a\u{0301}"]) {
      expect(isInvisibleOnly(text)).toBe(false);
    }
  });
});
