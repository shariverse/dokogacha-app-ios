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
});

describe("parseSaveProfileInput", () => {
  it("{ displayName } の形だけを受け付ける", () => {
    expect(parseSaveProfileInput({ displayName: "ゆい" })).toEqual({ displayName: "ゆい" });
    expect(() => parseSaveProfileInput("ゆい")).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
  });
});
