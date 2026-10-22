/**
 * 通知のトークン（`users/{uid}.fcmTokens`）が上限に近づいたときに、古いものから外す判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `tokenTrim.ts` が行う。
 *
 * アプリは自分のトークンを `arrayUnion` で直接足す（05 の §4）。セキュリティルールは 1 人 `MAX_TOKENS_PER_USER`（10）個までしか
 * 受け付けない（`firestore.rules` の `maxFcmTokens`）ので、消し損ねた古いトークンで 10 個たまると、新しい端末のトークンが拒否されて
 * 通知が届かなくなる（無効になったトークンは通知を送ったときに外すが、送るまでは残る）。
 * そこで、`users/{uid}` の更新で動くトリガーが `FCM_TOKENS_KEPT`（上限 − 1）個を超えた分を古い順に外し、次の 1 つを足せる余地を残す。
 * `arrayUnion` は一覧の末尾に足すので、先頭ほど古い。
 */
import { MAX_TOKENS_PER_USER } from "../notifications/logic";

/** トリガーが残す通知のトークンの数（ルールの上限より 1 つ少なくし、新しい端末のトークンを足せる余地を残す） */
export const FCM_TOKENS_KEPT = MAX_TOKENS_PER_USER - 1;

/**
 * 通知のトークンの一覧が多すぎれば、古いもの（先頭）を外した一覧を返す。
 * @param fcmTokens `users/{uid}.fcmTokens` の値
 * @returns 書き直す一覧（新しい順に `FCM_TOKENS_KEPT` 個。元の並びを保つ）。外すものが無い・一覧でなければ null（何も書かない）
 */
export function trimmedFcmTokens(fcmTokens: unknown): unknown[] | null {
  if (!Array.isArray(fcmTokens) || fcmTokens.length <= FCM_TOKENS_KEPT) {
    return null;
  }
  const list: readonly unknown[] = fcmTokens;
  return list.slice(list.length - FCM_TOKENS_KEPT);
}

/**
 * `users/{uid}` の更新で、トークンの一覧を外すかを確かめてよいか（トークンの数が残す数を超えたときだけ読みに行く）。
 * @param after 更新の後の `users/{uid}`（消されたときは undefined）
 */
export function shouldTrimFcmTokens(after: { fcmTokens?: unknown } | undefined): boolean {
  return trimmedFcmTokens(after?.fcmTokens) !== null;
}
