/**
 * 通知のトークン（`users/{uid}.fcmTokens`）を、古いものから外して `FCM_TOKENS_KEPT` 個にする（`onUserProfileUpdate` から呼ぶ）。
 * 何を残すかは `fcmTokens.ts` の `trimmedFcmTokens` が決める。
 */
import type { Firestore } from "firebase-admin/firestore";

import { userRef } from "../paths";
import { trimmedFcmTokens } from "./fcmTokens";

/**
 * トランザクションの中で読み直し、多すぎれば古いトークンを外して書く（同時に別の端末が足しても、読み直した値で判定する）。
 * 書いた結果はもう多すぎないので、この書き込みで動いたトリガーは何もしない（冪等）。
 * @param db Firestore（Admin SDK。ルールを通らない）
 * @param uid ユーザー
 * @returns 外したトークンの数
 */
export async function trimFcmTokens(db: Firestore, uid: string): Promise<number> {
  const ref = userRef(db, uid);
  return db.runTransaction(async (tx) => {
    const tokens: unknown = (await tx.get(ref)).get("fcmTokens");
    const trimmed = trimmedFcmTokens(tokens);
    if (trimmed === null || !Array.isArray(tokens)) {
      return 0;
    }
    tx.update(ref, { fcmTokens: trimmed });
    return tokens.length - trimmed.length;
  });
}
