import { readFileSync } from "node:fs";
import { join } from "node:path";

import { MAX_TOKENS_PER_USER } from "../notifications/logic";
import { FCM_TOKENS_KEPT, shouldTrimFcmTokens, trimmedFcmTokens } from "./fcmTokens";

/** `count` 個のトークン（古い順） */
function tokens(count: number): string[] {
  return Array.from({ length: count }, (_, index) => `t${String(index)}`);
}

describe("trimmedFcmTokens（通知のトークンの上限）", () => {
  it("残す数はルールの上限より 1 つ少ない（新しい端末のトークンを足せる余地を残す）", () => {
    expect(FCM_TOKENS_KEPT).toBe(MAX_TOKENS_PER_USER - 1);
    // firestore.rules の maxFcmTokens と同じ上限（片方だけを変えない）
    const rules = readFileSync(join(__dirname, "..", "..", "..", "firestore.rules"), "utf8");
    expect(rules).toMatch(new RegExp(`function maxFcmTokens\\(\\) \\{\\s*return ${String(MAX_TOKENS_PER_USER)};`, "u"));
  });

  it("残す数以下なら何も書かない", () => {
    expect(trimmedFcmTokens([])).toBeNull();
    expect(trimmedFcmTokens(tokens(FCM_TOKENS_KEPT))).toBeNull();
  });

  it("残す数を超えたら、古いもの（先頭）を外して新しい順に残す（並びは保つ）", () => {
    expect(trimmedFcmTokens(tokens(MAX_TOKENS_PER_USER))).toEqual(tokens(MAX_TOKENS_PER_USER).slice(1));
    expect(trimmedFcmTokens(tokens(FCM_TOKENS_KEPT + 1))).toEqual(tokens(FCM_TOKENS_KEPT + 1).slice(1));
    // 上限を超えた一覧（ルールの前に Admin SDK で書かれたものなど）も、残す数にする
    expect(trimmedFcmTokens(tokens(15))).toEqual(tokens(15).slice(15 - FCM_TOKENS_KEPT));
  });

  it("一覧でなければ何も書かない", () => {
    expect(trimmedFcmTokens(undefined)).toBeNull();
    expect(trimmedFcmTokens("t0")).toBeNull();
  });

  it("shouldTrimFcmTokens は、更新の後の数が残す数を超えたときだけ true", () => {
    expect(shouldTrimFcmTokens({ fcmTokens: tokens(MAX_TOKENS_PER_USER) })).toBe(true);
    expect(shouldTrimFcmTokens({ fcmTokens: tokens(FCM_TOKENS_KEPT) })).toBe(false);
    expect(shouldTrimFcmTokens({})).toBe(false);
    expect(shouldTrimFcmTokens(undefined)).toBe(false);
  });
});
