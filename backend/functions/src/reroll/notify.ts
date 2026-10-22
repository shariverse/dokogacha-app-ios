/**
 * 引き直しの提案の通知（02 の §8「引き直し提案 | 提案者以外 | {名前}さんが引き直しを提案しています」）の呼び出し口。
 * 通知を送る処理（宛先の決め方・FCM の送信）はタスク 32 で足す。今はログに残すだけで、何も送らない。
 *
 * 呼ぶのは、提案を書いたトランザクションが確定した後（トランザクションの中で呼ぶと、競合でやり直したときに 2 回送る）。
 * 同時に押してほかの人の提案に賛成として数えたときは呼ばない（提案は 1 回だけ）。
 */
import { logger } from "firebase-functions/v2";

/**
 * 引き直しが提案されたことを、提案者以外のメンバーに知らせる（タスク 32 で FCM を送る。今は何もしない）。
 * @param roomId 提案したルームの ID
 * @param proposedBy 提案した人の uid（文面の {名前} はルームのメンバーの表示名から読む）
 */
export function notifyRerollProposed(roomId: string, proposedBy: string): Promise<void> {
  logger.info("引き直しが提案された（通知はまだ送らない）", { roomId, proposedBy });
  return Promise.resolve();
}
