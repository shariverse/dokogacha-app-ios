/**
 * `updateRoomSettings`（02 の F-03）の入力の検証。
 * 状態によらない形・型・範囲だけをここで確かめ、今の設定と比べる決まり（引き上げのみ・状態ごとに変えられる項目）は `logic.ts` で確かめる。
 */
import { POST_LIMIT_RANGE, ROOM_NAME_LENGTH } from "../domain/constants";
import { isOneOf, LIKE_MODES, UNLOCK_RULES, type LikeMode, type UnlockRule } from "../domain/models";
import { appError } from "../errors";
import { requireDocumentId, requireIntegerInRange, requireObject, requireTrimmedText } from "../validation";

/**
 * `updateRoomSettings` の入力（検証済み）。変える項目だけに値がある（`undefined` は「変えない」）。
 * アプリ（Swift の `UpdateRoomSettingsRequest`）は nil の項目を鍵ごと送らない。`null` も「変えない」とみなす。
 */
export interface UpdateRoomSettingsInput {
  /** ルームの ID */
  roomId: string;
  /** ルーム名（前後の空白を取り除いた 1〜20 文字） */
  name?: string;
  /** 1 人あたりの投稿数（1〜10） */
  postLimit?: number;
  /** 解禁の条件 */
  unlockRule?: UnlockRule;
  /** 締切日時（UNIX 時刻のミリ秒。範囲は今の時刻と比べて `logic.ts` で確かめる） */
  deadlineAtMs?: number;
  /** いいねの効き方 */
  likeMode?: LikeMode;
}

/** 値が送られていないか（鍵が無い・null） */
function isAbsent(value: unknown): value is undefined | null {
  return value === undefined || value === null;
}

/**
 * `updateRoomSettings` の入力を検証する（`{ roomId, name?, postLimit?, unlockRule?, deadlineAt?, likeMode? }`）。
 * - `name`: 1〜20 文字（`createRoom` と同じ）・`postLimit`: 1〜10 の整数・`unlockRule`・`likeMode`: 決まった値
 * - `deadlineAt`: UNIX 時刻のミリ秒の整数。条件を「締切日時」以外に変えるのに締切日時を送ったら `invalid-argument`
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseUpdateRoomSettingsInput(data: unknown): UpdateRoomSettingsInput {
  const input = requireObject(data);
  const result: UpdateRoomSettingsInput = { roomId: requireDocumentId(input.roomId) };
  if (!isAbsent(input.name)) {
    result.name = requireTrimmedText(input.name, ROOM_NAME_LENGTH);
  }
  if (!isAbsent(input.postLimit)) {
    result.postLimit = requireIntegerInRange(input.postLimit, POST_LIMIT_RANGE);
  }
  if (!isAbsent(input.unlockRule)) {
    if (!isOneOf(UNLOCK_RULES, input.unlockRule)) {
      throw appError("invalid-argument");
    }
    result.unlockRule = input.unlockRule;
  }
  if (!isAbsent(input.deadlineAt)) {
    result.deadlineAtMs = requireIntegerInRange(input.deadlineAt, { min: 0, max: Number.MAX_SAFE_INTEGER });
    if (result.unlockRule !== undefined && result.unlockRule !== "deadline") {
      throw appError("invalid-argument");
    }
  }
  if (!isAbsent(input.likeMode)) {
    if (!isOneOf(LIKE_MODES, input.likeMode)) {
      throw appError("invalid-argument");
    }
    result.likeMode = input.likeMode;
  }
  return result;
}
