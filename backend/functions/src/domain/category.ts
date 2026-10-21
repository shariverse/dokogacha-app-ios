/**
 * 候補の場所のカテゴリ（02 の §3.1「カテゴリの対応表」）。
 * Swift 側の `Dokogacha/Domain/Category.swift`（`PlaceCategory`）と同じ値。
 * MapKit のカテゴリからの対応はアプリ（MapKit の検索結果を持つ側）だけで行うので、ここには値の一覧だけを置く。
 */

/**
 * カテゴリの保存する値（`candidates.category`・`pastIdeas.category`）。
 * tokens.json の `color.category` の鍵と同じ並び。
 */
export const PLACE_CATEGORIES = [
  "aquarium",
  "nature",
  "art",
  "food",
  "activity",
  "park",
  "town",
  "shrine",
  "sea",
] as const;

/** カテゴリ（9 種のいずれか） */
export type PlaceCategory = (typeof PLACE_CATEGORIES)[number];

/** 対応しきれないときのカテゴリ（02 の §3.1「対応しきれない場合は town にする」） */
export const FALLBACK_PLACE_CATEGORY: PlaceCategory = "town";

/**
 * 値がカテゴリのどれかか。Callable の入力（`addCandidate` の `category`）を検証するときに使う。
 * @param value 検証する値
 * @returns カテゴリなら true
 */
export function isPlaceCategory(value: unknown): value is PlaceCategory {
  return typeof value === "string" && (PLACE_CATEGORIES as readonly string[]).includes(value);
}
