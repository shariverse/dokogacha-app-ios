import { parseDisplayName, parseSaveProfileInput } from "./input";

// 02 の F-01「表示名 1〜10文字、必須」
describe("parseDisplayName", () => {
  it("1〜10 文字を受け付け、前後の空白を取り除く", () => {
    expect(parseDisplayName("ゆ")).toBe("ゆ");
    expect(parseDisplayName(" ゆい ")).toBe("ゆい");
    expect(parseDisplayName("あいうえおかきくけこ")).toBe("あいうえおかきくけこ");
  });

  it.each(["", "   ", "あいうえおかきくけこさ", 1, null])("%p は受け付けない", (value) => {
    expect(() => parseDisplayName(value)).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
  });

  it("1 文字でも UTF-16 で 160 を超える長さは受け付けない（結合文字をつないだ 1 文字）", () => {
    const name = `ゆ${"\u{3099}".repeat(159)}`;
    expect(parseDisplayName(name)).toBe(name);
    expect(() => parseDisplayName(`${name}\u{3099}`)).toThrow(
      expect.objectContaining({ code: "invalid-argument" }) as Error,
    );
  });
});

describe("parseSaveProfileInput", () => {
  it("{ displayName } の形だけを受け付ける", () => {
    expect(parseSaveProfileInput({ displayName: "ゆい" })).toEqual({ displayName: "ゆい" });
    expect(() => parseSaveProfileInput("ゆい")).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
  });
});
