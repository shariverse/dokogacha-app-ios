/**
 * アバターの色（`users.avatarColor`・`members.avatarColor` に保存する値）。
 * Swift 側は `Dokogacha/Domain/Models/AvatarPalette.swift`（`AvatarPalette`）。
 */
import { cryptoRandomInt, pickOne, type RandomInt } from "./random";

/** 保存する値の一覧（tokens.json の `color.avatar` と同じ順の `#RRGGBB`） */
export const AVATAR_COLORS = [
  "#B8321A",
  "#23775D",
  "#2F6FD0",
  "#A3367E",
  "#6B48C9",
  "#8A5A12",
  "#1F6E8C",
  "#5E5045",
] as const;

/** アバターの色 */
export type AvatarColor = (typeof AVATAR_COLORS)[number];

/**
 * ユーザーを作るときの色を選ぶ（06 の §4 の仮決め「ユーザー作成時にランダム。ルーム内の重複は許容」）。
 * @param random 乱数（既定は `crypto.randomInt`）
 * @returns 選んだ色の値
 */
export function pickAvatarColor(random: RandomInt = cryptoRandomInt): AvatarColor {
  return pickOne(AVATAR_COLORS, random);
}
