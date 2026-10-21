/**
 * Callable の入力（`request.data`）を検証するための共通の道具。
 * 入力は信用せず、形・型・範囲を確かめてから使う。正しくなければ `invalid-argument` を投げる。
 */
import { characters, containsForbiddenNameCharacter, isInvisibleOnly, trimWhitespace } from "./domain/text";
import { appError } from "./errors";

/** ドキュメントの ID（ルームの ID・uid）の最大の長さ（Firebase Auth の uid の上限 128 文字に合わせる） */
export const MAX_ID_LENGTH = 128;

/**
 * 名前（表示名・ルーム名）の 1 文字（書記素クラスタ）あたりに許す UTF-16 のコード単位の数。
 * 書記素の数だけで数えると、結合文字を何万個もつないだ 1 文字が通り、Firestore に巨大な文字列が書かれる
 * （表示名は参加のたびに members にコピーされる）。そこで文字列の長さにも「書記素の上限 × この値」の上限を設ける。
 * 16 にするのは、絵文字で最も長い RGI の並び（肌の色付きのキスする 2 人 👩🏻‍❤️‍💋‍👨🏼 が 15、イングランドの旗 🏴󠁧󠁢󠁥󠁮󠁧󠁿 が 14）でも
 * 上限の文字数まで入れられるようにするため。Swift 側は `String.utf16.count` で同じ上限を確かめる。
 */
export const MAX_UTF16_UNITS_PER_CHARACTER = 16;

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
 * 取り除いた後の UTF-16 のコード単位の数も `length.max × MAX_UTF16_UNITS_PER_CHARACTER` 以下であること。
 * 名前（表示名・ルーム名）に使うので、次も拒否する（取り除かずに入力エラーにする）。
 * - 途中に制御文字（改行・タブを含む `\p{Cc}`）・行区切り・段落区切りを含む
 * - 見えない文字（`\p{Cf}`・`\p{Default_Ignorable_Code_Point}`）と空白だけでできている（空とみなす）
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
  // 書記素に分ける前に長さを見て、巨大な文字列を分けずに断る
  if (trimmed.length > length.max * MAX_UTF16_UNITS_PER_CHARACTER) {
    throw appError("invalid-argument");
  }
  if (containsForbiddenNameCharacter(trimmed)) {
    throw appError("invalid-argument");
  }
  const count = isInvisibleOnly(trimmed) ? 0 : characters(trimmed).length;
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
