/**
 * 投稿の報告（02 の §3.5 F-14）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼ぶ）。
 *
 * 運営に送るメールの宛先は、Functions のパラメータ `REPORT_MAIL_TO` で受け取る（Discussion #5 の Q7。public リポジトリにアドレスを書かない）。
 * 値は `functions/.env.<プロジェクト ID>`（git の管理外）に人間が書くか、`firebase deploy` のときに聞かれて入れる。
 * メールそのものは Trigger Email 拡張（firestore-send-email。`backend/extensions/`）が `mail` を読んで SMTP で送る。
 *
 * `index.ts` の `setGlobalOptions` より先に読み込まれても東京に配置されるよう、リージョンは関数ごとにも指定する。
 */
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { defineString } from "firebase-functions/params";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "../callable";
import { FUNCTIONS_REGION } from "../config";
import { defaultDeps } from "../deps";
import * as reports from "./service";

/** 報告のメールの宛先（運営のアドレス。値はコミットしない） */
export const REPORT_MAIL_TO = defineString("REPORT_MAIL_TO", {
  description: "投稿の報告（F-14）を受け取る運営のメールアドレス（Trigger Email 拡張で送る）",
});

/** 候補を報告する（02 の §3.5。メンバーだけ・自分の投稿は不可・1 人 1 候補につき 1 回） */
export const reportCandidate = onCall({ region: FUNCTIONS_REGION }, (request) =>
  runCallable("reportCandidate", request, async (uid, data) => {
    const result = await reports.reportCandidate(defaultDeps(getFirestore()), uid, data, { to: REPORT_MAIL_TO.value() });
    if (!result.alreadyReported && !result.mailQueued) {
      // 報告は保存したが、宛先が空でメールを書けなかった（パラメータの入れ忘れ）
      logger.error("REPORT_MAIL_TO が空なので、報告のメールを書けませんでした", { uid });
    }
    return { alreadyReported: result.alreadyReported };
  }),
);
