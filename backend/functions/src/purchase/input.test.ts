import { MAX_SIGNED_TRANSACTION_LENGTH, parseVerifyPurchaseInput } from "./input";

/** 関数が指定した理由の HttpsError を投げることを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  expect(run).toThrow(expect.objectContaining({ details: { reason } }) as Error);
}

describe("parseVerifyPurchaseInput", () => {
  it("JWS の形の文字列を受け付ける（署名の部分が空のものも形としては通す。署名は verifier で確かめる）", () => {
    expect(parseVerifyPurchaseInput({ signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJhIjoxfQ.c2ln" })).toEqual({
      signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJhIjoxfQ.c2ln",
    });
    expect(parseVerifyPurchaseInput({ signedTransaction: "a.b." }).signedTransaction).toBe("a.b.");
  });

  it("文字列でない・JWS の形でない・長すぎる入力は invalid-argument", () => {
    for (const data of [
      null,
      "a.b.c",
      {},
      { signedTransaction: 1 },
      { signedTransaction: "" },
      { signedTransaction: "abc" },
      { signedTransaction: "a.b" },
      { signedTransaction: "a.b.c.d" },
      { signedTransaction: "a b.c.d" },
      { signedTransaction: "a+b.c/d.e=" },
      { signedTransaction: `${"a".repeat(MAX_SIGNED_TRANSACTION_LENGTH)}.b.c` },
    ]) {
      expectReason(() => parseVerifyPurchaseInput(data), "invalid-argument");
    }
  });
});
