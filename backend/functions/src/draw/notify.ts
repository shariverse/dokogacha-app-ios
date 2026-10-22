/**
 * 抽選の結果の通知（02 の §8「抽選結果 | 回した人以外 | 「{ルーム名}」の行き先が決まりました」）の呼び出し口。
 * 送る処理は `notifications/service.ts`（`sendRoomDrawn`）。送れなくてもログに残すだけで投げない。
 *
 * 呼ぶのは `onRoomDrawn`（ルームの更新のトリガー）で、`drawGacha` のトランザクションの中では呼ばない
 * （競合でやり直したときに 2 回送らないため）。トリガーは失敗するとやり直す（`retry: true`）が、
 * 送るのは抽選の ID ごとに 1 回（`notificationLogKey`）なので、やり直しで 2 回送らない。
 */
import { notifyQuietly, sendRoomDrawn, type NotificationDeps } from "../notifications/service";

/**
 * ルームの行き先が決まったことを、回した人以外のメンバーに知らせる。
 * @param deps 外部のもの（`ServiceDeps` をそのまま渡せる）
 * @param roomId 抽選したルームの ID
 * @param drawId 抽選の ID（`draws/{drawId}`。回した人 `drawnBy` はここから読む）
 */
export function notifyRoomDrawn(deps: NotificationDeps, roomId: string, drawId: string): Promise<void> {
  return notifyQuietly("drawn", { roomId, drawId }, () => sendRoomDrawn(deps, roomId, drawId));
}
