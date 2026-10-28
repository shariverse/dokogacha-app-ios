/**
 * 通知のトークン（`users/{uid}.fcmTokens`）が残す数を超えたら、`users/{uid}` の更新で動くトリガー（`onUserProfileUpdate`）が
 * 古いものから外すことを Emulator で確かめる（ルールの上限 10 個で新しい端末のトークンが拒否されないように）。
 * トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る。
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { MAX_TOKENS_PER_USER } from "../../functions/src/notifications/logic";
import { FCM_TOKENS_KEPT } from "../../functions/src/users/fcmTokens";
import { trimFcmTokens } from "../../functions/src/users/tokenTrim";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;

/** `count` 個のトークン（古い順） */
function tokens(count: number, prefix = "t"): string[] {
  return Array.from({ length: count }, (_, index) => `${prefix}${String(index)}`);
}

describe("通知のトークンの整理（onUserProfileUpdate）", () => {
  let app: App;
  let db: Firestore;

  async function addUser(uid: string, fcmTokens: string[]): Promise<void> {
    await db.doc(`users/${uid}`).set({ displayName: uid, avatarColor: AVATAR_COLORS[0], adFree: false, fcmTokens, createdAt: Timestamp.now() });
  }

  async function tokensOf(uid: string): Promise<unknown> {
    return (await db.doc(`users/${uid}`).get()).get("fcmTokens");
  }

  /** `uid` のトークンが `expected` になるまで読み直す */
  async function waitForTokens(uid: string, expected: string[]): Promise<void> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    let last: unknown;
    while (Date.now() < deadline) {
      last = await tokensOf(uid);
      if (JSON.stringify(last) === JSON.stringify(expected)) {
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${uid} のトークンが ${JSON.stringify(expected)} にならない（最後: ${JSON.stringify(last)}）`);
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("fcm-tokens"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("上限の 10 個目を足したら、トリガーが一番古いものを外して 9 個にする（次の端末のトークンを足せる）", async () => {
    await addUser("fcm-alice", tokens(FCM_TOKENS_KEPT));
    await db.doc("users/fcm-alice").update({ fcmTokens: FieldValue.arrayUnion("new") });
    await waitForTokens("fcm-alice", [...tokens(FCM_TOKENS_KEPT).slice(1), "new"]);
  });

  it("残す数以下の更新では外さない（表示名だけの更新も）", async () => {
    await addUser("fcm-bob", tokens(FCM_TOKENS_KEPT - 1));
    await db.doc("users/fcm-bob").update({ fcmTokens: FieldValue.arrayUnion("new") });
    await expect(trimFcmTokens(db, "fcm-bob")).resolves.toBe(0);
    expect(await tokensOf("fcm-bob")).toEqual([...tokens(FCM_TOKENS_KEPT - 1), "new"]);
  });

  it("trimFcmTokens は読み直した値で判定し、上限を超えた一覧も残す数にする（冪等）", async () => {
    await addUser("fcm-carol", tokens(MAX_TOKENS_PER_USER + 3));
    await expect(trimFcmTokens(db, "fcm-carol")).resolves.toBe(4);
    expect(await tokensOf("fcm-carol")).toEqual(tokens(MAX_TOKENS_PER_USER + 3).slice(4));
    await expect(trimFcmTokens(db, "fcm-carol")).resolves.toBe(0);
    await expect(trimFcmTokens(db, "fcm-nobody")).resolves.toBe(0);
  });
});
