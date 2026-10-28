/**
 * アカウントの削除（02 の §2.6 F-06・05 の §5 の `deleteAccount`）の判定（Firestore に触れない純粋な関数）。
 * Firestore と Auth の読み書きは `service.ts` が行い、何をするかはここで決めて Jest で確かめる。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Account.swift`）も同じ規則で判定する。
 *
 * 削除するとき、参加中のルームごとに次のどれかを行う:
 * - 作成者で、まだ終了していないルーム（`open`・`unlocked`・`drawn`）: 終了（`closed`）し、同じ書き込みで本人をメンバーから外す。
 *   02 の F-06「作成者だったルームは closed にする」。作成者は退出できない（F-05）ので、終了したルームからも外して、
 *   終了で動く過去のアイデアの登録（`onRoomClosed`）の宛先を残るメンバーだけにする
 * - それ以外（作成者でないルーム・作成者でも終了済みのルーム）: 退出と同じ処理で外す（02 の F-06「F-05 と同じ処理」）。
 *   終了したルームからも外す（メンバーの一覧に表示名と色の複製が残らないように）
 */
import type { RoomDoc } from "../domain/models";

/** 1 つのルームで行うこと。`none` = 何もしない（もうメンバーでない）・`leave` = 退出と同じ・`closeAndLeave` = 終了して外す */
export type AccountDeletionAction = "none" | "leave" | "closeAndLeave";

/** 判定に使うルームの値（壊れたデータでもよい） */
export type AccountDeletionRoom = Partial<Pick<RoomDoc, "ownerId" | "status">> & { memberIds?: unknown };

/**
 * アカウントを削除する人が、1 つのルームで何をするかを決める。
 *
 * `memberIds` にいなければ何もしない（前の呼び出しで外し終えたルーム。やり直しても同じルームを二度書かない）。
 * 作成者で `closed` でなければ終了して外す。ほかは退出と同じに外す。
 * @param room ルーム
 * @param uid 削除する人
 * @returns 行うこと
 */
export function accountDeletionActionOf(room: AccountDeletionRoom, uid: string): AccountDeletionAction {
  if (!Array.isArray(room.memberIds) || !room.memberIds.includes(uid)) {
    return "none";
  }
  if (room.ownerId === uid && room.status !== "closed") {
    return "closeAndLeave";
  }
  return "leave";
}

/**
 * Auth のユーザーを消そうとしたときのエラーが「もういない」か（前の呼び出しで消し終えている。削除をやり直しても失敗にしない）。
 * @param error Admin SDK の `deleteUser` が投げたエラー
 */
export function isAuthUserNotFound(error: unknown): boolean {
  return typeof error === "object" && error !== null && (error as { code?: unknown }).code === "auth/user-not-found";
}
