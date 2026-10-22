import { REMOVE_ADS_PRODUCT_ID } from "../domain/constants";
import {
  decidePurchase,
  joinedBefore,
  parseAppAppleId,
  sponsorAfterPurchase,
  verificationEnvironments,
  type SponsorAfterPurchaseInput,
} from "./logic";

describe("decidePurchase（02 の §7.2 の非消耗型アイテム remove_ads）", () => {
  it("remove_ads で取り消されていなければ受け付ける", () => {
    expect(decidePurchase({ productId: REMOVE_ADS_PRODUCT_ID, revocationDate: undefined })).toEqual({ kind: "grant" });
  });

  it("別のアイテム・アイテムの無いものは断る", () => {
    expect(decidePurchase({ productId: "coins_100", revocationDate: undefined })).toEqual({ kind: "reject", why: "other-product" });
    expect(decidePurchase({ productId: undefined, revocationDate: undefined })).toEqual({ kind: "reject", why: "other-product" });
  });

  it("返金などで取り消された購入は断る", () => {
    expect(decidePurchase({ productId: REMOVE_ADS_PRODUCT_ID, revocationDate: 1_760_000_000_000 })).toEqual({
      kind: "reject",
      why: "revoked",
    });
  });
});

describe("verificationEnvironments", () => {
  it("本番はアプリの ID があれば Production → Sandbox（審査・TestFlight の購入も受け付ける）", () => {
    expect(verificationEnvironments({ emulator: false, appAppleId: 1234567890 })).toEqual(["Production", "Sandbox"]);
  });

  it("アプリの ID がまだ無ければ Sandbox だけ", () => {
    expect(verificationEnvironments({ emulator: false, appAppleId: undefined })).toEqual(["Sandbox"]);
  });

  it("Xcode の StoreKit のテストの署名は Emulator でだけ受け付ける", () => {
    expect(verificationEnvironments({ emulator: true, appAppleId: undefined })).toEqual(["Xcode", "Sandbox"]);
    expect(verificationEnvironments({ emulator: true, appAppleId: 1 })).toEqual(["Xcode", "Sandbox"]);
    expect(verificationEnvironments({ emulator: false, appAppleId: 1 })).not.toContain("Xcode");
  });
});

describe("parseAppAppleId", () => {
  it("数字だけの値を数にする（前後の空白は取り除く）", () => {
    expect(parseAppAppleId("1234567890")).toBe(1234567890);
    expect(parseAppAppleId(" 42 ")).toBe(42);
  });

  it("空・数字でない・0 始まり・大きすぎる値は undefined（まだ登録していない扱い）", () => {
    for (const value of ["", "  ", "abc", "12a", "-1", "0", "0123", "1.5", "99999999999999999999"]) {
      expect(parseAppAppleId(value)).toBeUndefined();
    }
  });
});

describe("joinedBefore", () => {
  it("参加日時の早い方が先。同じ日時なら uid の小さい方（orderBy(joinedAt) とドキュメントの ID の順）", () => {
    expect(joinedBefore({ uid: "b", joinedAtMs: 1 }, { uid: "a", joinedAtMs: 2 })).toBe(true);
    expect(joinedBefore({ uid: "a", joinedAtMs: 2 }, { uid: "b", joinedAtMs: 1 })).toBe(false);
    expect(joinedBefore({ uid: "a", joinedAtMs: 5 }, { uid: "b", joinedAtMs: 5 })).toBe(true);
    expect(joinedBefore({ uid: "b", joinedAtMs: 5 }, { uid: "a", joinedAtMs: 5 })).toBe(false);
  });
});

describe("sponsorAfterPurchase（05 の §3「購入者がいれば最初に参加した人」）", () => {
  const buyer = { uid: "bob", displayName: "ぼぶ", joinedAtMs: 200 };

  function input(overrides: Partial<SponsorAfterPurchaseInput>): SponsorAfterPurchaseInput {
    return { current: null, buyer, currentJoin: null, ...overrides };
  }

  it("購入者がいなければ、購入した人にする", () => {
    expect(sponsorAfterPurchase(input({}))).toEqual({ uid: "bob", displayName: "ぼぶ" });
  });

  it("先に参加した購入者がいれば変えない", () => {
    const current = { uid: "alice", displayName: "ありす" };
    expect(sponsorAfterPurchase(input({ current, currentJoin: { uid: "alice", joinedAtMs: 100 } }))).toBeNull();
  });

  it("購入した人のほうが先に参加していれば、購入した人に替える", () => {
    const current = { uid: "carol", displayName: "きゃろる" };
    expect(sponsorAfterPurchase(input({ current, currentJoin: { uid: "carol", joinedAtMs: 300 } }))).toEqual({
      uid: "bob",
      displayName: "ぼぶ",
    });
  });

  it("同じ日時なら uid の小さい方を先にする", () => {
    const current = { uid: "carol", displayName: "きゃろる" };
    expect(sponsorAfterPurchase(input({ current, currentJoin: { uid: "carol", joinedAtMs: 200 } }))).toEqual({
      uid: "bob",
      displayName: "ぼぶ",
    });
    const earlier = { uid: "amy", displayName: "えいみー" };
    expect(sponsorAfterPurchase(input({ current: earlier, currentJoin: { uid: "amy", joinedAtMs: 200 } }))).toBeNull();
  });

  it("すでに購入した人が購入者なら変えない（何度呼んでも書かない）", () => {
    const current = { uid: "bob", displayName: "ぼぶ" };
    expect(sponsorAfterPurchase(input({ current, currentJoin: { uid: "bob", joinedAtMs: 200 } }))).toBeNull();
    expect(sponsorAfterPurchase(input({ current, currentJoin: null }))).toBeNull();
  });

  it("いまの購入者のメンバーのドキュメントが無ければ、購入した人にする", () => {
    const current = { uid: "gone", displayName: "いない人" };
    expect(sponsorAfterPurchase(input({ current, currentJoin: null }))).toEqual({ uid: "bob", displayName: "ぼぶ" });
  });
});
