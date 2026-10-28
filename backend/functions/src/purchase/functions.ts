/**
 * 広告非表示の買い切り（02 の §7.2 F-51）の Cloud Functions。`index.ts` がここから export する。
 * 処理の中身は `service.ts` にあり、ここでは Callable に包み、署名の検証（App Store Server Library）を作って渡すだけにする。
 *
 * 検証に使う値は Functions のパラメータで受け取る（鍵・秘密は要らない。署名の検証は公開のルート証明書だけで行う）:
 * - `APP_STORE_BUNDLE_ID`: アプリの Bundle ID（既定は `jp.shilokuma.Dokogacha`）
 * - `APP_STORE_APP_APPLE_ID`: App Store Connect のアプリの ID（数字）。空のあいだは Production の検証をせず、Sandbox（審査・TestFlight）だけを受け付ける
 * 値は `functions/.env.<プロジェクト ID>`（git の管理外）に人間が書くか、`firebase deploy` のときに入れる。Emulator は `.env.demo-dokogacha`。
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
import { isEmulatorEnvironment } from "../notifications/sender";
import { parseAppAppleId } from "./logic";
import * as purchase from "./service";
import { appleTransactionVerifier, type TransactionVerifier } from "./verifier";

/** アプリの Bundle ID（`Configs/Project.xcconfig` の `PRODUCT_BUNDLE_IDENTIFIER`） */
export const APP_STORE_BUNDLE_ID = defineString("APP_STORE_BUNDLE_ID", {
  description: "広告非表示の購入（F-51）の署名を確かめるアプリの Bundle ID",
  default: "jp.shilokuma.Dokogacha",
});

/** App Store Connect のアプリの ID（Apple ID。数字。アプリを登録するまでは空） */
export const APP_STORE_APP_APPLE_ID = defineString("APP_STORE_APP_APPLE_ID", {
  description: "App Store Connect のアプリの Apple ID（数字）。空なら Production の購入を確かめず、Sandbox だけを受け付ける",
  default: "",
});

/** 作った検証（パラメータは起動の後に変わらないので、最初に呼ばれたときに 1 回だけ作る） */
let cachedVerifier: TransactionVerifier | undefined;

/** 本番（と Emulator の Functions）で使う、署名の検証 */
function verifier(): TransactionVerifier {
  cachedVerifier ??= appleTransactionVerifier({
    bundleId: APP_STORE_BUNDLE_ID.value(),
    appAppleId: parseAppAppleId(APP_STORE_APP_APPLE_ID.value()),
    emulator: isEmulatorEnvironment(process.env),
  });
  return cachedVerifier;
}

/** 広告非表示の購入をサーバーで確かめて記録する（02 の §7.2。`users.adFree` と参加中のルームの `adFreeSponsor`） */
export const verifyPurchase = onCall({ region: FUNCTIONS_REGION }, (request) =>
  runCallable("verifyPurchase", request, async (uid, data) => {
    const result = await purchase.verifyPurchase(defaultDeps(getFirestore()), uid, data, verifier());
    logger.info("広告非表示の購入を記録した", { uid, ...result });
    return { adFree: result.adFree };
  }),
);
