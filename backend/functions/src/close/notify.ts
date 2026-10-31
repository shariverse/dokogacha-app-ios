/**
 * 途中の終了の通知（Discussion #155 の Q5「{作成者}さんが「{ルーム名}」を終了しました」。宛先は作成者以外）の呼び出し口。
 * 送る処理は `notifications/service.ts`（`sendRoomEnded`）。送れなくてもログに残すだけで投げない。
 *
 * 呼ぶのは、S-12 の「ルームを終了する」（`closeRoom` の `endEarly`）で終了したトランザクションが確定した後だけ
 * （トランザクションの中で呼ぶと、競合でやり直したときに 2 回送る）。もう終了していた（二度押し）ときは呼ばない。
 * 「この行き先で決定」・抽選から 7 日の自動の終了・アカウントの削除で終了したときは送らない
 * （行き先が決まった通知は抽選のときに送ってある。アカウントの削除では作成者がいなくなるので「{作成者}さんが終了しました」の文面にならない）。
 */
import { notifyQuietly, sendRoomEnded, type NotificationDeps } from "../notifications/service";

/**
 * 作成者がルームを途中で終了したことを、作成者以外のメンバーに知らせる。
 * @param deps 外部のもの（`ServiceDeps` をそのまま渡せる）
 * @param roomId 終了したルームの ID
 * @param endedBy 終了した人（作成者）の uid
 */
export function notifyRoomEnded(deps: NotificationDeps, roomId: string, endedBy: string): Promise<void> {
  return notifyQuietly("roomEnded", { roomId, endedBy }, () => sendRoomEnded(deps, roomId, endedBy));
}
