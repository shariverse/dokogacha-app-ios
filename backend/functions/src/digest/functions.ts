/**
 * 新しい候補のまとめ通知（02 の §8）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここではスケジュールに包むだけにする（Emulator のテストは中身を直接呼ぶ）。
 *
 * `index.ts` の `setGlobalOptions` より先に読み込まれても東京に配置されるよう、リージョンは関数ごとにも指定する。
 */
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { FUNCTIONS_REGION } from "../config";
import { defaultDeps } from "../deps";
import { SCHEDULE_TIME_ZONE } from "../domain/constants";
import { digestSchedule } from "./logic";
import { sendNewCandidateDigests } from "./service";

/**
 * その日（前の日の 20:00〜今日の 20:00 JST）に候補が増えたルームのメンバーに、まとめて知らせる
 * （05 の §5「1日1回、20:00 JST」。06 の §4 の仮決め）。同じルームには 1 日 1 回だけ。
 * 一部のルームで失敗しても残りを送ってから投げる
 */
export const notifyNewCandidates = onSchedule(
  { region: FUNCTIONS_REGION, schedule: digestSchedule(), timeZone: SCHEDULE_TIME_ZONE },
  async () => {
    const result = await sendNewCandidateDigests(defaultDeps(getFirestore()));
    logger.info("新しい候補のまとめ通知を処理した", result);
  },
);
