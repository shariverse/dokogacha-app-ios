import { readFileSync } from "node:fs";
import { join } from "node:path";

import { AVATAR_COLORS, pickAvatarColor } from "./avatarPalette";
import { FALLBACK_PLACE_CATEGORY, isPlaceCategory, PLACE_CATEGORIES } from "./category";
import {
  initialRerollState,
  isOneOf,
  LIKE_MODES,
  MEMBER_ROLES,
  REPORT_REASONS,
  REROLL_STATUSES,
  ROOM_STATUSES,
  UNLOCK_RULES,
} from "./models";

// 05 の §3 の値と、デザインの正本（docs/spec/design/tokens.json）との突き合わせ。
// Swift 側の DomainModelsTests・PlaceCategoryTests・DesignTokensTests と同じ値を確かめる。

/** リポジトリの docs/spec/design/tokens.json の color（このファイルは backend/functions/src/domain/ にある） */
const tokenColors = (
  JSON.parse(
    readFileSync(join(__dirname, "..", "..", "..", "..", "docs", "spec", "design", "tokens.json"), "utf8"),
  ) as { color: { category: Record<string, unknown>; avatar: string[] } }
).color;

describe("状態・条件・モードの値", () => {
  it("05 の §3 のとおり", () => {
    expect(ROOM_STATUSES).toEqual(["open", "unlocked", "drawn", "closed"]);
    expect(UNLOCK_RULES).toEqual(["all", "majority", "deadline"]);
    expect(LIKE_MODES).toEqual(["boost", "equal"]);
    expect(MEMBER_ROLES).toEqual(["owner", "member"]);
    expect(REROLL_STATUSES).toEqual(["none", "voting", "passed", "rejected"]);
    expect(REPORT_REASONS).toEqual(["inappropriate", "spam", "other"]);
  });

  it("isOneOf は一覧の文字列だけを受け付ける", () => {
    expect(isOneOf(ROOM_STATUSES, "open")).toBe(true);
    expect(isOneOf(ROOM_STATUSES, "OPEN")).toBe(false);
    expect(isOneOf(ROOM_STATUSES, 1)).toBe(false);
    expect(isOneOf(ROOM_STATUSES, undefined)).toBe(false);
  });

  it("ルームの作成時の引き直しは「提案されていない」", () => {
    expect(initialRerollState()).toEqual({ used: false, votesFor: [], votesAgainst: [], status: "none" });
  });
});

describe("カテゴリ", () => {
  it("9 種で、tokens.json の color.category の鍵と同じ", () => {
    expect(PLACE_CATEGORIES).toEqual(["aquarium", "nature", "art", "food", "activity", "park", "town", "shrine", "sea"]);
    expect([...PLACE_CATEGORIES].sort()).toEqual(Object.keys(tokenColors.category).sort());
  });

  it("対応しきれないときは街歩き", () => {
    expect(FALLBACK_PLACE_CATEGORY).toBe("town");
  });

  it("isPlaceCategory は 9 種の文字列だけを受け付ける", () => {
    expect(isPlaceCategory("shrine")).toBe(true);
    expect(isPlaceCategory("museum")).toBe(false);
    expect(isPlaceCategory(null)).toBe(false);
  });
});

describe("アバターの色", () => {
  it("tokens.json の color.avatar と同じ順の #RRGGBB", () => {
    expect([...AVATAR_COLORS]).toEqual(tokenColors.avatar.map((hex) => hex.toUpperCase()));
  });

  it("注入した乱数で一覧から選ぶ", () => {
    expect(pickAvatarColor(() => 0)).toBe("#B8321A");
    expect(pickAvatarColor((max) => max - 1)).toBe("#5E5045");
    expect(AVATAR_COLORS).toContain(pickAvatarColor());
  });
});
