import { requireDocumentId, requireIntegerInRange, requireObject, requireTrimmedText } from "./validation";

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
