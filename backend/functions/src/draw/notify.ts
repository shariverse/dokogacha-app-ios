/**
 * 抽選の結果の通知（02 の §8「抽選結果 | 回した人以外 | 「{ルーム名}」の行き先が決まりました」）の呼び出し口。
 * 通知を送る処理（宛先の決め方・FCM の送信）はタスク 32 で足す。今はログに残すだけで、何も送らない。
 *
 * 呼ぶのは `onRoomDrawn`（ルームの更新のトリガー）で、`drawGacha` のトランザクションの中では呼ばない
 * （競合でやり直したときに 2 回送らないため）。トリガーは失敗するとやり直す（`retry: true`）ので、
 * 送る処理を足すときは、同じ抽選の ID で 2 回送らないようにする（例: 抽選の記録に送った印を残す）。
 */
import { logger } from "firebase-functions/v2";

/**
 * ルームの行き先が決まったことを、回した人以外のメンバーに知らせる（タスク 32 で FCM を送る。今は何もしない）。
 * @param roomId 抽選したルームの ID
 * @param drawId 抽選の ID（`draws/{drawId}`。回した人 `drawnBy` はここから読む）
 */
export function notifyRoomDrawn(roomId: string, drawId: string): Promise<void> {
  logger.info("ルームの行き先が決まった（通知はまだ送らない）", { roomId, drawId });
  return Promise.resolve();
}
