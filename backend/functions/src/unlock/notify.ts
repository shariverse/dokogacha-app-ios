/**
 * 解禁したときの通知（02 の §5.2「解禁されたらメンバー全員にプッシュ通知（F-60）」）の呼び出し口。
 * 送る処理は `notifications/service.ts`（`sendRoomUnlocked`）。送れなくてもログに残すだけで投げない。
 *
 * 呼ぶのは、`open` から `unlocked` に変えたトランザクションが確定した後（トランザクションの中で呼ぶと、
 * 競合でやり直したときに 2 回送る）。トリガーのやり直し（`retry`）では、もう `unlocked` なので呼ばれない。
 * 準備OKの付け外しで `open`⇄`unlocked` を繰り返しても、送るのはルームにつき 1 回（`notificationLogKey`）。
 */
import type { UnlockReason } from "../domain/unlock";
import { notifyQuietly, sendRoomUnlocked, type NotificationDeps } from "../notifications/service";

/**
 * ルームが解禁されたことをメンバー全員に知らせる。
 * 文面は理由（強制解禁を含む）によらず 02 の §8 の「「{ルーム名}」のガチャが解禁されました！」にする。
 * @param deps 外部のもの（`ServiceDeps` をそのまま渡せる）
 * @param roomId 解禁したルームの ID
 * @param reason 解禁した理由（ログに残す）
 */
export function notifyRoomUnlocked(deps: NotificationDeps, roomId: string, reason: UnlockReason): Promise<void> {
  return notifyQuietly("unlocked", { roomId, reason }, () => sendRoomUnlocked(deps, roomId));
}
