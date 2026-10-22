/**
 * 引き直しの提案の通知（02 の §8「引き直し提案 | 提案者以外 | {名前}さんが引き直しを提案しています」）の呼び出し口。
 * 送る処理は `notifications/service.ts`（`sendRerollProposed`）。送れなくてもログに残すだけで投げない。
 *
 * 呼ぶのは、提案を書いたトランザクションが確定した後（トランザクションの中で呼ぶと、競合でやり直したときに 2 回送る）。
 * 同時に押してほかの人の提案に賛成として数えたときは呼ばない（提案は 1 回だけ）。
 */
import { notifyQuietly, sendRerollProposed, type NotificationDeps } from "../notifications/service";

/**
 * 引き直しが提案されたことを、提案者以外のメンバーに知らせる。
 * @param deps 外部のもの（`ServiceDeps` をそのまま渡せる）
 * @param roomId 提案したルームの ID
 * @param proposedBy 提案した人の uid（文面の {名前} はルームのメンバーの表示名から読む）
 */
export function notifyRerollProposed(deps: NotificationDeps, roomId: string, proposedBy: string): Promise<void> {
  return notifyQuietly("rerollProposed", { roomId, proposedBy }, () => sendRerollProposed(deps, roomId, proposedBy));
}
