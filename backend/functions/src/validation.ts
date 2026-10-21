/**
 * Callable の入力（`request.data`）を検証するための共通の道具。
 * 入力は信用せず、形・型・範囲を確かめてから使う。正しくなければ `invalid-argument` を投げる。
 */
import { characters, trimWhitespace } from "./domain/text";
import { appError } from "./errors";

/** ドキュメントの ID（ルームの ID・uid）の最大の長さ（Firebase Auth の uid の上限 128 文字に合わせる） */
export const MAX_ID_LENGTH = 128;

/**
 * 入力がオブジェクト（配列・null でない）か確かめる。
 * @param data `request.data`
 * @returns キーで値を引けるオブジェクト
 * @throws `invalid-argument`
 */
export function requireObject(data: unknown): Record<string, unknown> {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw appError("invalid-argument");
  }
  return data as Record<string, unknown>;
}

/**
 * ドキュメントの ID として使える文字列か確かめる（パスの区切り `/` を含まない・`.`・`..` でない・長すぎない）。
 * 入力の ID でパスを組み立てるので、別のコレクションを指せないようにする。
 * @param value 入力の値
 * @returns ID
 * @throws `invalid-argument`
 */
export function requireDocumentId(value: unknown): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAX_ID_LENGTH ||
    value.includes("/") ||
    value === "." ||
    value === ".." ||
    /^__.*__$/u.test(value)
  ) {
    throw appError("invalid-argument");
  }
  return value;
}

/**
 * 前後の空白を取り除いた文字数（書記素クラスタ）が範囲に入る文字列か確かめる。
 * @param value 入力の値
 * @param length 文字数の範囲（両端を含む）
 * @returns 前後の空白を取り除いた文字列
 * @throws `invalid-argument`
 */
export function requireTrimmedText(value: unknown, length: { min: number; max: number }): string {
  if (typeof value !== "string") {
    throw appError("invalid-argument");
  }
  const trimmed = trimWhitespace(value);
  const count = characters(trimmed).length;
  if (count < length.min || count > length.max) {
    throw appError("invalid-argument");
  }
  return trimmed;
}

/**
 * 範囲に入る整数か確かめる。
 * @param value 入力の値
 * @param range 範囲（両端を含む）
 * @returns 整数
 * @throws `invalid-argument`
 */
export function requireIntegerInRange(value: unknown, range: { min: number; max: number }): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < range.min || value > range.max) {
    throw appError("invalid-argument");
  }
  return value;
}
