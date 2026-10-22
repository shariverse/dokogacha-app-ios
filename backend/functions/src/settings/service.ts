/**
 * ルーム設定の変更（05 の §5 の `updateRoomSettings`・02 の F-03）。
 * 変更ルールは `logic.ts` の `planSettingsUpdate`、入力の検証は `input.ts`。
 *
 * 設定を変えたら、同じトランザクションでメンバーを数え直して解禁を判定し直す（`unlock/logic.ts` の `planUnlock`）。
 * 解禁の条件を `open` で変えると、その場で `unlocked` になることがある（例: 全員OK → 過半数OK で、すでに過半数が準備OK）。
 * 条件は `open` でしか変えられないので、設定の変更で `unlocked` から `open` に戻ることはない。
 */
import { Timestamp } from "firebase-admin/firestore";

import type { RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { roomRef } from "../paths";
import { planUnlock } from "../unlock/logic";
import { notifyRoomUnlocked } from "../unlock/notify";
import { readMemberCounts, unlockStateOf } from "../unlock/service";
import { parseUpdateRoomSettingsInput } from "./input";
import { planSettingsUpdate } from "./logic";

/**
 * 作成者がルームの設定を変える（02 の F-03）。変える項目が無ければ（すべて今と同じ）何も書かない。
 * @param deps 外部のもの
 * @param uid 呼んだ人（作成者であること）
 * @param data `request.data`（`{ roomId, name?, postLimit?, unlockRule?, deadlineAt?, likeMode? }`）
 */
export async function updateRoomSettings(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const input = parseUpdateRoomSettingsInput(data);
  const { db } = deps;
  const ref = roomRef(db, input.roomId);
  const unlockedBy = await db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    const nowMs = deps.nowMs();
    const state = unlockStateOf(room);
    const changes = planSettingsUpdate(
      {
        status: room.status,
        ownerId: room.ownerId,
        name: room.name,
        postLimit: room.settings.postLimit,
        unlockRule: room.settings.unlockRule,
        deadlineAtMs: state.deadlineAtMs,
        likeMode: room.settings.likeMode,
      },
      uid,
      input,
      nowMs,
    );
    if (Object.keys(changes).length === 0) {
      return null;
    }
    // トランザクションは読み取りを書き込みより先に済ませる決まりなので、書く前にメンバーを読む
    const counts = await readMemberCounts(tx, ref);
    const plan = planUnlock(
      {
        ...state,
        unlockRule: changes.unlockRule ?? state.unlockRule,
        deadlineAtMs: changes.deadlineAtMs === undefined ? state.deadlineAtMs : changes.deadlineAtMs,
      },
      counts,
      nowMs,
    );
    // ネストしたフィールド（`settings.postLimit`）を書くので、キーを文字列で持つ
    const update: Record<string, unknown> = { ...plan.update };
    if (changes.name !== undefined) {
      update.name = changes.name;
    }
    if (changes.postLimit !== undefined) {
      update["settings.postLimit"] = changes.postLimit;
    }
    if (changes.unlockRule !== undefined) {
      update["settings.unlockRule"] = changes.unlockRule;
    }
    if (changes.deadlineAtMs !== undefined) {
      update["settings.deadlineAt"] = changes.deadlineAtMs === null ? null : Timestamp.fromMillis(changes.deadlineAtMs);
    }
    if (changes.likeMode !== undefined) {
      update["settings.likeMode"] = changes.likeMode;
    }
    tx.update(ref, update);
    return plan.unlockedBy;
  });
  if (unlockedBy !== null) {
    await notifyRoomUnlocked(input.roomId, unlockedBy);
  }
  return {};
}
