/**
 * ルームの Callable（`createRoom`・`joinRoom`・`leaveRoom`・`removeMember`）の入力の検証。
 * 05 の §5 の入力を、型・範囲を確かめてから使う形にする。
 */
import {
  DEADLINE_EARLIEST_FROM_NOW_MS,
  DEADLINE_LATEST_FROM_NOW_MS,
  POST_LIMIT_RANGE,
  ROOM_NAME_LENGTH,
} from "../domain/constants";
import { parseInviteCode } from "../domain/inviteCode";
import { isOneOf, LIKE_MODES, UNLOCK_RULES, type LikeMode, type UnlockRule } from "../domain/models";
import { appError } from "../errors";
import { requireDocumentId, requireIntegerInRange, requireObject, requireTrimmedText } from "../validation";

/**
 * 締切日時の下限（今から 1 時間後）に持たせる猶予（ミリ秒）。
 * アプリの日時ピッカーは「今から 1 時間後」を下限にするので、ちょうど下限を選んで送ると、
 * 届くまでの時間で下限を少し割る。そのぶんを受け付ける（サーバーだけで使う値）。
 */
export const DEADLINE_EARLIEST_GRACE_MS = 5 * 60 * 1000;

/** `createRoom` の入力（検証済み） */
export interface CreateRoomInput {
  /** ルーム名（前後の空白を取り除いた 1〜20 文字） */
  name: string;
  /** 1 人あたりの投稿数（1〜10） */
  postLimit: number;
  /** 解禁の条件 */
  unlockRule: UnlockRule;
  /** 締切日時（UNIX 時刻のミリ秒）。`unlockRule` が `deadline` のときだけ値があり、それ以外は null */
  deadlineAtMs: number | null;
  /** いいねの効き方 */
  likeMode: LikeMode;
}

/**
 * `createRoom` の入力を検証する（02 の F-02 の入力項目）。
 * - `name`: 1〜20 文字（前後の空白を取り除いて数える）
 * - `postLimit`: 1〜10 の整数
 * - `unlockRule`: `all` / `majority` / `deadline`
 * - `deadlineAt`: `unlockRule` が `deadline` のときだけ必須。UNIX 時刻のミリ秒で、サーバーの今から 1 時間後〜30 日後
 *   （Callable の入力は JSON なので `Timestamp` を送れない）。それ以外の条件では送らない（`null` は可）
 * - `likeMode`: `boost` / `equal`
 * @param data `request.data`
 * @param nowMs サーバーの今の時刻（UNIX 時刻のミリ秒）
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseCreateRoomInput(data: unknown, nowMs: number): CreateRoomInput {
  const input = requireObject(data);
  const name = requireTrimmedText(input.name, ROOM_NAME_LENGTH);
  const postLimit = requireIntegerInRange(input.postLimit, POST_LIMIT_RANGE);
  if (!isOneOf(UNLOCK_RULES, input.unlockRule) || !isOneOf(LIKE_MODES, input.likeMode)) {
    throw appError("invalid-argument");
  }
  const unlockRule = input.unlockRule;
  let deadlineAtMs: number | null = null;
  if (unlockRule === "deadline") {
    deadlineAtMs = requireIntegerInRange(input.deadlineAt, {
      min: nowMs + DEADLINE_EARLIEST_FROM_NOW_MS - DEADLINE_EARLIEST_GRACE_MS,
      max: nowMs + DEADLINE_LATEST_FROM_NOW_MS,
    });
  } else if (input.deadlineAt !== undefined && input.deadlineAt !== null) {
    throw appError("invalid-argument");
  }
  return { name, postLimit, unlockRule, deadlineAtMs, likeMode: input.likeMode };
}

/** `joinRoom` の入力（検証済み） */
export interface JoinRoomInput {
  /** 招待コード（正規化したハイフンなしの 6 文字） */
  inviteCode: string;
}

/**
 * `joinRoom` の入力（`{ inviteCode }`）を検証する。
 * 招待コードはサーバーでも正規化する（小文字・ハイフン・全角・空白を受け付ける。アプリと同じ規則）。
 * 文字列でなければ `invalid-argument`、招待コードの形でなければ「招待コードが見つかりません」（存在しないコードと同じ扱い）。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`・`invite-code-not-found`
 */
export function parseJoinRoomInput(data: unknown): JoinRoomInput {
  const input = requireObject(data);
  if (typeof input.inviteCode !== "string") {
    throw appError("invalid-argument");
  }
  const inviteCode = parseInviteCode(input.inviteCode);
  if (inviteCode === null) {
    throw appError("invite-code-not-found");
  }
  return { inviteCode };
}

/** `leaveRoom` の入力（検証済み） */
export interface LeaveRoomInput {
  /** ルームの ID */
  roomId: string;
}

/**
 * `leaveRoom` の入力（`{ roomId }`）を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseLeaveRoomInput(data: unknown): LeaveRoomInput {
  const input = requireObject(data);
  return { roomId: requireDocumentId(input.roomId) };
}

/** `removeMember` の入力（検証済み） */
export interface RemoveMemberInput {
  /** ルームの ID */
  roomId: string;
  /** 削除するメンバーの uid */
  memberId: string;
}

/**
 * `removeMember` の入力（`{ roomId, memberId }`）を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseRemoveMemberInput(data: unknown): RemoveMemberInput {
  const input = requireObject(data);
  return { roomId: requireDocumentId(input.roomId), memberId: requireDocumentId(input.memberId) };
}
