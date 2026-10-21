/**
 * ユーザーのプロフィール（`users/{uid}`）を作る・表示名を変える処理（`saveProfile`）。
 *
 * `users/{uid}` を作る経路は資料に無いので、05 の §4 の方針（整合性が要る書き込みは Callable）に沿って Callable にした。
 * アバターの色（06 の §4「ユーザー作成時にランダム」）と `adFree = false` をサーバーで決め、クライアントが自分を
 * 購入済みにしたり、パレットに無い色を書いたりできないようにする。表示名の変更（S-15）も同じ Callable で行い、
 * 文字数をアプリと同じ数え方（書記素クラスタ）で検証する。
 */
import { FieldValue } from "firebase-admin/firestore";

import { pickAvatarColor } from "../domain/avatarPalette";
import type { UserDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { userRef } from "../paths";
import { parseSaveProfileInput } from "./input";

/** `saveProfile` の結果 */
export interface SaveProfileResult {
  /** 保存した表示名 */
  displayName: string;
  /** アバターの色（作ったときに決めた色。表示名を変えても変わらない） */
  avatarColor: string;
  /** 今回ユーザーを作ったか（初回の表示名の登録） */
  created: boolean;
}

/**
 * 表示名を保存する。ユーザーがまだ無ければ作る（02 の F-01 の初回の表示名の入力）。
 * 参加中のルームのメンバーの表示名（参加時点のコピー）は、ここでは変えない（05 の §5 の `onUserProfileUpdate`）。
 * @param deps 外部のもの
 * @param uid 呼んだ人
 * @param data `request.data`（`{ displayName }`）
 * @returns 保存した値
 */
export async function saveProfile(deps: ServiceDeps, uid: string, data: unknown): Promise<SaveProfileResult> {
  const { displayName } = parseSaveProfileInput(data);
  const ref = userRef(deps.db, uid);
  return deps.db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const existing = snapshot.data() as UserDoc | undefined;
    if (existing !== undefined) {
      tx.update(ref, { displayName });
      return { displayName, avatarColor: existing.avatarColor, created: false };
    }
    const avatarColor = pickAvatarColor(deps.random);
    tx.create(ref, {
      displayName,
      avatarColor,
      adFree: false,
      fcmTokens: [],
      createdAt: FieldValue.serverTimestamp(),
    });
    return { displayName, avatarColor, created: true };
  });
}
