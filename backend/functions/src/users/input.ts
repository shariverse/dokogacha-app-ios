/**
 * ユーザーのプロフィールの Callable（`saveProfile`）の入力の検証。
 */
import { DISPLAY_NAME_LENGTH } from "../domain/constants";
import { requireObject, requireTrimmedText } from "../validation";

/** `saveProfile` の入力 */
export interface SaveProfileInput {
  /** 表示名（前後の空白を取り除いた 1〜10 文字） */
  displayName: string;
}

/**
 * 表示名を検証する（02 の F-01「1〜10文字、必須」）。前後の空白は取り除いてから数える（空白だけの名前は空とみなす）。
 * @param value 入力の値
 * @returns 前後の空白を取り除いた表示名
 * @throws `invalid-argument`
 */
export function parseDisplayName(value: unknown): string {
  return requireTrimmedText(value, DISPLAY_NAME_LENGTH);
}

/**
 * `saveProfile` の入力（`{ displayName }`）を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseSaveProfileInput(data: unknown): SaveProfileInput {
  const input = requireObject(data);
  return { displayName: parseDisplayName(input.displayName) };
}
