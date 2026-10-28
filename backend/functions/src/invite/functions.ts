/**
 * 前回のメンバーへの招待（02 の §2.4 F-04）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼ぶ）。
 *
 * `index.ts` の `setGlobalOptions` より先に読み込まれても東京に配置されるよう、リージョンは関数ごとにも指定する。
 */
import { getFirestore } from "firebase-admin/firestore";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "../callable";
import { FUNCTIONS_REGION } from "../config";
import { defaultDeps } from "../deps";
import * as invite from "./service";

/** 呼んだ人が参加した直近の終了したルームのメンバーに、今のルームへの招待を通知で送る（今のルームごとに、同じ前回のルームからは 1 回だけ） */
export const inviteLastMembers = onCall({ region: FUNCTIONS_REGION }, (request) =>
  runCallable("inviteLastMembers", request, (uid, data) => invite.inviteLastMembers(defaultDeps(getFirestore()), uid, data)),
);
