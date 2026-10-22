/**
 * ルーム設定の変更ルール（02 の F-03）の判定（Firestore に触れない純粋な関数）。
 *
 * | 項目 | 変更ルール（02 の §2.3） |
 * | --- | --- |
 * | ルーム名 | いつでも変更可（`closed` 以外） |
 * | 投稿数 | 引き上げのみ可（下げられない） |
 * | 解禁の条件（締切日時を含む） | `open` のときのみ変更可 |
 * | いいねの効き方 | `open`/`unlocked` のときのみ変更可 |
 *
 * - 変えられるのは作成者だけ。`closed` のルームは閲覧のみ（02 の §2.1）なので、どの項目も変えられない
 * - 今と同じ値を送った項目は「変えない」とみなし、状態の決まりで断らない（S-12 が全項目を送っても、変えた項目だけで判定する）
 * - 投稿数は 02 に状態の決まりが無いので、`closed` 以外ならいつでも引き上げられる（引き直しで `unlocked` に戻ると投稿できる）
 */
import { DEADLINE_EARLIEST_FROM_NOW_MS, DEADLINE_LATEST_FROM_NOW_MS } from "../domain/constants";
import type { LikeMode, RoomStatus, UnlockRule } from "../domain/models";
import { appError } from "../errors";
import { DEADLINE_EARLIEST_GRACE_MS } from "../rooms/input";
import type { UpdateRoomSettingsInput } from "./input";

/** いいねの効き方を変えられる状態（02 の F-03「open/unlocked のときのみ」） */
const LIKE_MODE_EDITABLE_STATUSES: readonly RoomStatus[] = ["open", "unlocked"];

/** 変更の判定に使う、今のルームの値（締切日時はミリ秒） */
export interface CurrentRoomSettings {
  /** 状態 */
  status: RoomStatus;
  /** 作成者の uid */
  ownerId: string;
  /** ルーム名 */
  name: string;
  /** 1 人あたりの投稿数 */
  postLimit: number;
  /** 解禁の条件 */
  unlockRule: UnlockRule;
  /** 締切日時のミリ秒（条件が「締切日時」でなければ null） */
  deadlineAtMs: number | null;
  /** いいねの効き方 */
  likeMode: LikeMode;
}

/** 変える項目（今と違うものだけ。空なら何も書かない） */
export interface SettingsChanges {
  /** ルーム名 */
  name?: string;
  /** 1 人あたりの投稿数 */
  postLimit?: number;
  /** 解禁の条件 */
  unlockRule?: UnlockRule;
  /** 締切日時のミリ秒（条件を「締切日時」以外にするときは null で消す） */
  deadlineAtMs?: number | null;
  /** いいねの効き方 */
  likeMode?: LikeMode;
}

/**
 * 変えた後の解禁の条件と締切日時を決め、変えてよいか確かめる。
 * 条件を「締切日時」にするときは締切日時が要る（今が「締切日時」なら今の締切日時を引き継ぐ）。
 * 「締切日時」以外にするときは締切日時を消す（null）。新しい締切日時は `createRoom` と同じ範囲（今から 1 時間後（5 分の猶予）〜30 日後）。
 */
function planUnlockRule(
  room: CurrentRoomSettings,
  input: UpdateRoomSettingsInput,
  nowMs: number,
): Pick<SettingsChanges, "unlockRule" | "deadlineAtMs"> {
  const unlockRule = input.unlockRule ?? room.unlockRule;
  let deadlineAtMs: number | null = null;
  if (unlockRule === "deadline") {
    deadlineAtMs = input.deadlineAtMs ?? (room.unlockRule === "deadline" ? room.deadlineAtMs : null);
    if (deadlineAtMs === null) {
      throw appError("invalid-argument");
    }
  } else if (input.deadlineAtMs !== undefined) {
    // 条件を送らずに締切日時だけを送ったが、今の条件が「締切日時」でない
    throw appError("invalid-argument");
  }
  if (unlockRule === room.unlockRule && deadlineAtMs === room.deadlineAtMs) {
    return {};
  }
  if (room.status !== "open") {
    throw appError("unlock-rule-locked");
  }
  if (
    deadlineAtMs !== null &&
    deadlineAtMs !== room.deadlineAtMs &&
    (deadlineAtMs < nowMs + DEADLINE_EARLIEST_FROM_NOW_MS - DEADLINE_EARLIEST_GRACE_MS ||
      deadlineAtMs > nowMs + DEADLINE_LATEST_FROM_NOW_MS)
  ) {
    throw appError("invalid-argument");
  }
  const changes: Pick<SettingsChanges, "unlockRule" | "deadlineAtMs"> = { deadlineAtMs };
  if (unlockRule !== room.unlockRule) {
    changes.unlockRule = unlockRule;
  }
  return changes;
}

/**
 * 設定の変更を、02 の F-03 の変更ルールで確かめて、変える項目を決める。
 * 確かめる順: 作成者か → `closed` でないか → ルーム名 → 投稿数（引き上げのみ）→ 解禁の条件（`open` のみ）→ いいねの効き方（`open`・`unlocked` のみ）
 * @param room 今のルームの値
 * @param uid 呼んだ人
 * @param input 検証した入力
 * @param nowMs サーバーの今の時刻（新しい締切日時の範囲に使う）
 * @returns 変える項目（今と違うものだけ）
 * @throws `not-room-owner`・`room-closed`・`post-limit-decrease`・`unlock-rule-locked`・`like-mode-locked`・`invalid-argument`
 */
export function planSettingsUpdate(
  room: CurrentRoomSettings,
  uid: string,
  input: UpdateRoomSettingsInput,
  nowMs: number,
): SettingsChanges {
  if (room.ownerId !== uid) {
    throw appError("not-room-owner");
  }
  if (room.status === "closed") {
    throw appError("room-closed");
  }
  const changes: SettingsChanges = {};
  if (input.name !== undefined && input.name !== room.name) {
    changes.name = input.name;
  }
  if (input.postLimit !== undefined && input.postLimit !== room.postLimit) {
    if (input.postLimit < room.postLimit) {
      throw appError("post-limit-decrease");
    }
    changes.postLimit = input.postLimit;
  }
  Object.assign(changes, planUnlockRule(room, input, nowMs));
  if (input.likeMode !== undefined && input.likeMode !== room.likeMode) {
    if (!LIKE_MODE_EDITABLE_STATUSES.includes(room.status)) {
      throw appError("like-mode-locked");
    }
    changes.likeMode = input.likeMode;
  }
  return changes;
}
