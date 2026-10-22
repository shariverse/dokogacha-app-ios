/**
 * ルームの終了（02 の §6.5 F-44）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここでは Callable・スケジュール・トリガーに包むだけにする（Emulator のテストは中身を直接呼ぶ）。
 *
 * `index.ts` の `setGlobalOptions` より先に読み込まれても東京に配置されるよう、リージョンは関数ごとにも指定する。
 */
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { runCallable } from "../callable";
import { FUNCTIONS_REGION } from "../config";
import { defaultDeps } from "../deps";
import { SCHEDULE_TIME_ZONE } from "../domain/constants";
import type { RoomDoc } from "../domain/models";
import { AUTO_CLOSE_SCHEDULE, roomClosedBy } from "./logic";
import * as close from "./service";

/** Callable の処理が使う外部のもの（呼ばれたときに作る。読み込みの時点では Firestore に繋がない） */
const deps = () => defaultDeps(getFirestore());

/** 作成者がルームを終了する（02 の §6.3「この行き先で決定」。`drawn` のときだけ。もう終了していれば何もしない） */
export const closeRoom = onCall({ region: FUNCTIONS_REGION }, (request) =>
  runCallable("closeRoom", request, (uid, data) => close.closeRoom(deps(), uid, data)),
);

/**
 * 抽選から 7 日たった `drawn` のルームを `closed` にする（02 の §6.5・05 の §5。1 日 1 回。06 の §4 の仮決め 7 日）。
 * 一部のルームで失敗しても残りを処理してから投げる（次の実行でもう一度拾う）
 */
export const autoCloseRooms = onSchedule(
  { region: FUNCTIONS_REGION, schedule: AUTO_CLOSE_SCHEDULE, timeZone: SCHEDULE_TIME_ZONE },
  async () => {
    const result = await close.closeOverdueRooms(deps());
    if (result.rooms > 0) {
      logger.info("抽選から 7 日たったルームを終了した", result);
    }
  },
);

/**
 * ルームが `closed` になったら（作成者の決定・自動の終了のどちらでも）、当選しなかった候補を、
 * 終了したときの各メンバー（`event.data.after` の `memberIds`。やり直しでも同じ値）の過去のアイデアに登録する（02 の §6.5・F-13。Firestore のトリガー）。
 * `closed` のままの更新では何もしない。失敗したらやり直す（`retry: true`。登録は冪等）
 */
export const onRoomClosed = onDocumentUpdated(
  { region: FUNCTIONS_REGION, document: "rooms/{roomId}", retry: true },
  async (event) => {
    const before = event.data?.before.data() as Partial<RoomDoc> | undefined;
    const after = event.data?.after.data() as Partial<RoomDoc> | undefined;
    if (!roomClosedBy(before, after)) {
      return;
    }
    const roomId = event.params.roomId;
    // 終了した時点のルームの値を渡す（読み直すと、直後に退出・削除された人が宛先から外れる）
    const registered = await close.registerPastIdeas(getFirestore(), roomId, after);
    logger.info("終了したルームの過去のアイデアを登録した", { roomId, registered });
  },
);
