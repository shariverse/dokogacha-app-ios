/**
 * アカウントの削除（02 の §2.6 F-06）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼ぶ）。
 *
 * `index.ts` の `setGlobalOptions` より先に読み込まれても東京に配置されるよう、リージョンは関数ごとにも指定する。
 */
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "../callable";
import { FUNCTIONS_REGION } from "../config";
import * as account from "./service";

/**
 * 呼んだ人のアカウントを削除する（02 の F-06。参加中のルームから退出・作成者のルームは終了・`users/{uid}` と過去のアイデアと Auth のユーザーを削除）。
 * 途中で失敗しても、もう一度呼べば続きから終わる
 */
export const deleteAccount = onCall({ region: FUNCTIONS_REGION }, (request) =>
  runCallable("deleteAccount", request, async (uid) => {
    const result = await account.deleteAccount(
      { db: getFirestore(), deleteAuthUser: async (target) => getAuth().deleteUser(target) },
      uid,
    );
    logger.info("アカウントを削除した", { uid, ...result });
    return {};
  }),
);
