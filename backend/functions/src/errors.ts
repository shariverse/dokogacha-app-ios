/**
 * Callable Functions が返すエラーと、アプリに出す文言の対応（この 1 か所にまとめる）。
 *
 * - アプリは `HttpsError` の `details.reason`（下の `AppErrorReason`）で文言を選ぶ。`code` は gRPC の分類で、
 *   再試行してよいか（`unavailable`）などの判断に使う。同じ `code` に別の理由が複数あるため、文言は `reason` で引く
 * - `message` にもアプリの文言を入れる（ログで読めるように。アプリはローカライズのため自分の文言の表を持つ。タスク 11）
 * - 文言は 02・03 にあればその表記どおり（F-04 の AC など）。無いものはこのファイルで決める
 * - 想定していない例外は `internal`（「通信できませんでした」）にする（`callable.ts`）
 */
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import { MAX_MEMBERS } from "./domain/constants";

/** エラーの理由ごとの、gRPC のコードとアプリの文言 */
export const APP_ERRORS = {
  /** サインインしていない（匿名認証の前に呼んだ） */
  unauthenticated: { code: "unauthenticated", message: "通信できませんでした" },
  /** 入力の形が正しくない（アプリが検証してから呼ぶので、通常は出ない） */
  "invalid-argument": { code: "invalid-argument", message: "入力内容を確認してください" },
  /** 表示名を登録する前に、ルームを作成・参加しようとした（S-01 を通っていない） */
  "profile-required": { code: "failed-precondition", message: "表示名を登録してください" },
  /** 招待コードが存在しない・形が正しくない（02 の F-04 の AC） */
  "invite-code-not-found": { code: "not-found", message: "招待コードが見つかりません" },
  /** メンバーが上限に達している（02 の F-04 の AC） */
  "room-full": { code: "resource-exhausted", message: `このルームは満員です（最大${String(MAX_MEMBERS)}人）` },
  /** ルームが `drawn`・`closed` で参加できない（02 の F-04 の AC） */
  "room-already-decided": { code: "failed-precondition", message: "このルームはもう行き先が決まっています" },
  /** ルームが存在しない */
  "room-not-found": { code: "not-found", message: "ルームが見つかりません" },
  /** ルームのメンバーではない */
  "not-room-member": { code: "permission-denied", message: "このルームのメンバーではありません" },
  /** 作成者だけができる操作を、作成者以外が呼んだ */
  "not-room-owner": { code: "permission-denied", message: "作成者だけが操作できます" },
  /** 作成者は退出できない（02 の F-05「作成者は退出できない（MVP）」） */
  "owner-cannot-leave": { code: "failed-precondition", message: "作成者はルームから退出できません" },
  /** 作成者を削除しようとした（作成者は退出できないので、削除もできない） */
  "cannot-remove-owner": { code: "failed-precondition", message: "作成者は削除できません" },
  /** 削除しようとした人が、もうメンバーにいない */
  "member-not-found": { code: "not-found", message: "このメンバーはもうルームにいません" },
  /** 招待コードを決められなかった（重複が続いた。もう一度呼べば通る見込みが高い） */
  "invite-code-unavailable": { code: "unavailable", message: "通信できませんでした" },
  /** 想定していないエラー */
  internal: { code: "internal", message: "通信できませんでした" },
} as const satisfies Record<string, { code: FunctionsErrorCode; message: string }>;

/** エラーの理由（`HttpsError` の `details.reason` の値） */
export type AppErrorReason = keyof typeof APP_ERRORS;

/** `HttpsError` の `details` の形 */
export interface AppErrorDetails {
  /** エラーの理由 */
  reason: AppErrorReason;
}

/**
 * 理由に対応する `HttpsError` を作る。Callable の中で `throw appError("room-full")` のように使う。
 * @param reason エラーの理由
 * @returns アプリに返すエラー
 */
export function appError(reason: AppErrorReason): HttpsError {
  const { code, message } = APP_ERRORS[reason];
  const details: AppErrorDetails = { reason };
  return new HttpsError(code, message, details);
}
