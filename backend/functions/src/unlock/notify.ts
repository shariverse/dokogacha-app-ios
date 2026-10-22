/**
 * 解禁したときの通知（02 の §5.2「解禁されたらメンバー全員にプッシュ通知（F-60）」）の呼び出し口。
 * 通知を送る処理（宛先の決め方・FCM の送信）はタスク 32 で足す。今はログに残すだけで、何も送らない。
 *
 * 呼ぶのは、`open` から `unlocked` に変えたトランザクションが確定した後（トランザクションの中で呼ぶと、
 * 競合でやり直したときに 2 回送る）。トリガーのやり直し（`retry`）では、もう `unlocked` なので呼ばれない。
 */
import { logger } from "firebase-functions/v2";

import type { UnlockReason } from "../domain/unlock";

/**
 * ルームが解禁されたことをメンバーに知らせる（タスク 32 で FCM を送る。今は何もしない）。
 * @param roomId 解禁したルームの ID
 * @param reason 解禁した理由（`forced` なら「作成者が解禁しました」の文面にする）
 */
export function notifyRoomUnlocked(roomId: string, reason: UnlockReason): Promise<void> {
  logger.info("ルームを解禁した（通知はまだ送らない）", { roomId, reason });
  return Promise.resolve();
}
