/**
 * ルームの終了の Callable（`closeRoom`）の入力の検証。
 */
import { appError } from "../errors";
import { requireDocumentId, requireObject } from "../validation";

/**
 * 終了の意図（アプリの `CloseRoomRequest.Reason`）。
 * - `decide`: S-14 の「この行き先で決定」（`drawn` のルームを終了する）
 * - `endEarly`: S-12 の「ルームを終了する」（抽選の前の `open`・`unlocked` のルームを途中で終了する）
 *
 * 意図をサーバーで今の状態と突き合わせ、確認のダイアログを出している間にほかの人がガチャを回したときに、
 * 途中でやめるつもりの操作で `drawn` のルームを終了させない（Discussion #155 の Q3）
 */
export const CLOSE_REASONS = ["decide", "endEarly"] as const;

/** 終了の意図 */
export type CloseReason = (typeof CLOSE_REASONS)[number];

/** `closeRoom` の入力（検証済み） */
export interface CloseRoomInput {
  /** ルームの ID */
  roomId: string;
  /** 終了の意図 */
  reason: CloseReason;
}

/**
 * `{ roomId, reason }` の入力を検証する。`reason` が無いときは `decide`（意図を送らない前の版のアプリの「この行き先で決定」）。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`（ルームの ID が正しくない・`reason` が知らない値）
 */
export function parseCloseRoomInput(data: unknown): CloseRoomInput {
  const input = requireObject(data);
  const roomId = requireDocumentId(input.roomId);
  if (input.reason === undefined) {
    return { roomId, reason: "decide" };
  }
  if (!CLOSE_REASONS.some((reason) => reason === input.reason)) {
    throw appError("invalid-argument");
  }
  return { roomId, reason: input.reason as CloseReason };
}
