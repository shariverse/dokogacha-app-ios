/**
 * プッシュ通知（02 の §8 F-60）を Emulator で確かめる。Emulator には FCM が無いので、送った通知は
 * `emulatorPushOutbox`（`notifications/sender.ts` の `emulatorOutboxSender`）に書かれる。そこを読んで「何を誰に送ったか」を確かめる。
 * - 解禁: Functions の Emulator の `onMemberWrite` が解禁したら全メンバーに送る。`open`⇄`unlocked` を繰り返しても 1 回だけ
 * - 抽選結果: `drawGacha` で `drawn` になると、Functions の Emulator の `onRoomDrawn` が回した人以外に送る（PR #62 の持ち越し）
 * - 引き直しの提案: `proposeReroll` が提案者以外に送る
 * - 「登録されていない」トークンを `users.fcmTokens` から外す。送る処理が失敗しても投げない
 *
 * トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `notify-` を付ける。
 */
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import type { RandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { drawGacha } from "../../functions/src/draw/service";
import { notifyRoomDrawn } from "../../functions/src/draw/notify";
import { EMULATOR_OUTBOX_COLLECTION, EMULATOR_UNREGISTERED_TOKEN_PREFIX, type PushMessage } from "../../functions/src/notifications/sender";
import { NOTIFICATION_LOG_COLLECTION, sendRoomUnlocked } from "../../functions/src/notifications/service";
import { proposeReroll } from "../../functions/src/reroll/service";
import { notifyRoomUnlocked } from "../../functions/src/unlock/notify";
import { recountRoom } from "../../functions/src/unlock/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;

/** 決まった値を返す乱数 */
const fixed: RandomInt = () => 0;

/** メンバー（先頭が作成者）とトークン。carol はトークンが無い（通知を許可していない） */
const MEMBERS = ["alice", "bob", "carol"];
/** メンバーの表示名（ルームの中のコピー。引き直しの提案の文面の {名前}） */
const NAMES: Record<string, string> = { alice: "ありす", bob: "ぼぶ", carol: "きゃろる" };
const TOKENS: Record<string, string[]> = {
  alice: ["alice-token"],
  bob: ["bob-token", `${EMULATOR_UNREGISTERED_TOKEN_PREFIX}bob-old`],
  carol: [],
};

describe("プッシュ通知（F-60）", () => {
  let app: App;
  let db: Firestore;

  function deps(): ServiceDeps {
    return { db, random: fixed, nowMs: () => Date.now() };
  }

  /** `check` が通るまで読み直す（固定の時間で待たない） */
  async function waitUntil<T>(read: () => Promise<T>, check: (value: T) => boolean, label: string): Promise<T> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    let last = await read();
    while (!check(last)) {
      if (Date.now() > deadline) {
        throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${label} にならない（最後: ${JSON.stringify(last)}）`);
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
      last = await read();
    }
    return last;
  }

  /** そのルームに送った通知（`type` で絞る） */
  async function outbox(roomId: string, type: string): Promise<PushMessage[]> {
    const snapshot = await db.collection(EMULATOR_OUTBOX_COLLECTION).where("threadId", "==", roomId).get();
    return snapshot.docs.map((doc) => doc.data() as PushMessage).filter((message) => message.data.type === type);
  }

  /** 送ったトークン（並びは問わない） */
  function tokensOf(messages: PushMessage[]): string[] {
    return messages.map((message) => message.token).sort();
  }

  async function roomStatus(roomId: string): Promise<unknown> {
    return (await db.doc(`rooms/${roomId}`).get()).data()?.status;
  }

  /**
   * ルームを作る（メンバーは `MEMBERS`、`ready` の人は準備OK。候補が 1 件）。数え直しが済むまで待ってから返す
   */
  async function addRoom(roomId: string, options: { status: string; ready: string[] }): Promise<void> {
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: MEMBERS[0],
      inviteCode: "NTFYQQ",
      status: options.status,
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
      forcedUnlock: false,
      memberIds: MEMBERS,
      memberCount: -1,
      readyCount: -1,
      candidateCount: 1,
      adFreeSponsor: null,
      currentDrawId: null,
      winnerCandidateId: null,
      excludedCandidateIds: [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
      createdAt: Timestamp.now(),
      drawnAt: null,
      closedAt: null,
    });
    for (const uid of MEMBERS) {
      await db.doc(`users/${uid}`).set({
        displayName: NAMES[uid] ?? uid,
        avatarColor: AVATAR_COLORS[0],
        adFree: false,
        fcmTokens: TOKENS[uid] ?? [],
        createdAt: Timestamp.now(),
      });
    }
    // open のルームは、メンバーを書いている途中で（そろう前に）全員OKと判定されないよう、全員を準備OKでない状態で作ってから付ける
    const initiallyReady = options.status === "open" ? [] : options.ready;
    for (const [index, uid] of MEMBERS.entries()) {
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: NAMES[uid] ?? uid,
        avatarColor: AVATAR_COLORS[0],
        role: index === 0 ? "owner" : "member",
        ready: initiallyReady.includes(uid),
        joinedAt: Timestamp.fromMillis(Date.now() + index),
        lastSeenAt: Timestamp.now(),
      });
    }
    await db.doc(`rooms/${roomId}/candidates/c-a`).set({
      place: { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: null },
      category: "sea",
      note: "",
      url: null,
      postedBy: "alice",
      postedByName: "ありす",
      colorIndex: 0,
      likedBy: [],
      fromPastIdeaId: null,
      createdAt: Timestamp.now(),
    });
    await waitForCounts(roomId, initiallyReady.length);
    if (options.status === "open") {
      for (const uid of options.ready) {
        await setReady(roomId, uid, true);
      }
      await waitForCounts(roomId, options.ready.length);
    }
  }

  /** トリガーが数え直して、メンバー数と準備OKの数が `ready` になるまで待つ */
  async function waitForCounts(roomId: string, ready: number): Promise<void> {
    await waitUntil(
      async () => {
        const room = (await db.doc(`rooms/${roomId}`).get()).data();
        return { memberCount: room?.memberCount as unknown, readyCount: room?.readyCount as unknown };
      },
      (counts) => counts.memberCount === MEMBERS.length && counts.readyCount === ready,
      `数え直し（準備OK ${String(ready)} 人）`,
    );
  }

  async function setReady(roomId: string, uid: string, ready: boolean): Promise<void> {
    await db.doc(`rooms/${roomId}/members/${uid}`).update({ ready });
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("notifications"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("全員が準備OKになって解禁したら、トークンのあるメンバー全員に送り、無効なトークンを外す", async () => {
    const roomId = "notify-unlock";
    await addRoom(roomId, { status: "open", ready: ["alice", "bob"] });
    await setReady(roomId, "carol", true);

    const sent = await waitUntil(() => outbox(roomId, "unlocked"), (messages) => messages.length >= 2, "解禁の通知");
    expect(tokensOf(sent)).toEqual(["alice-token", "bob-token"]);
    expect(sent[0]).toMatchObject({
      body: "「年末の旅行」のガチャが解禁されました！",
      data: { type: "unlocked", roomId, target: "room" },
    });
    // 「登録されていない」で失敗したトークンだけを外す
    await waitUntil(
      async () => (await db.doc("users/bob").get()).data()?.fcmTokens as unknown,
      (tokens) => JSON.stringify(tokens) === JSON.stringify(["bob-token"]),
      "bob の無効なトークンを外す",
    );
    expect((await db.doc("users/alice").get()).data()?.fcmTokens).toEqual(["alice-token"]);
  });

  it("準備OKの付け外しで open⇄unlocked を繰り返しても、解禁の通知はルームにつき 1 回だけ", async () => {
    const roomId = "notify-unlock-once";
    await addRoom(roomId, { status: "open", ready: ["alice", "bob"] });
    await setReady(roomId, "carol", true);
    await waitUntil(() => outbox(roomId, "unlocked"), (messages) => messages.length >= 2, "1 回目の解禁の通知");

    await setReady(roomId, "carol", false);
    await waitUntil(() => roomStatus(roomId), (status) => status === "open", "open に戻る");
    await setReady(roomId, "carol", true);
    await waitUntil(() => roomStatus(roomId), (status) => status === "unlocked", "もう一度 unlocked");
    // トリガーと重なっても、印（notificationLog）があるので 2 回目は送らない
    await recountRoom(deps(), roomId);
    await notifyRoomUnlocked(deps(), roomId, "allReady");

    expect(await outbox(roomId, "unlocked")).toHaveLength(2);
    const log = await db.doc(`rooms/${roomId}/${NOTIFICATION_LOG_COLLECTION}/unlocked`).get();
    expect(log.exists).toBe(true);
  });

  it("ガチャを回すと、onRoomDrawn が回した人以外に結果を送る（やり直しでも 2 回送らない）", async () => {
    const roomId = "notify-drawn";
    await addRoom(roomId, { status: "unlocked", ready: MEMBERS });
    const result = await drawGacha(deps(), "alice", { roomId });

    const sent = await waitUntil(() => outbox(roomId, "drawn"), (messages) => messages.length >= 1, "抽選結果の通知");
    // alice（回した人）を外し、carol はトークンが無い。bob の無効なトークンは失敗して外れる
    expect(tokensOf(sent)).toEqual(["bob-token"]);
    expect(sent[0]).toMatchObject({
      body: "「年末の旅行」の行き先が決まりました",
      data: { type: "drawn", roomId, target: "result", drawId: result.drawId },
    });

    // トリガーのやり直しと同じ呼び出しをもう一度しても、同じ抽選の通知は送らない
    await notifyRoomDrawn(deps(), roomId, result.drawId);
    expect(await outbox(roomId, "drawn")).toHaveLength(1);
  });

  it("引き直しを提案すると、提案者以外に「{名前}さんが引き直しを提案しています」を送る", async () => {
    const roomId = "notify-reroll";
    await addRoom(roomId, { status: "unlocked", ready: MEMBERS });
    const result = await drawGacha(deps(), "carol", { roomId });
    await proposeReroll(deps(), "bob", { roomId });

    const sent = await outbox(roomId, "rerollProposed");
    expect(tokensOf(sent)).toEqual(["alice-token"]);
    expect(sent[0]).toMatchObject({
      body: "ぼぶさんが引き直しを提案しています",
      data: { type: "rerollProposed", roomId, target: "result", drawId: result.drawId },
    });
  });

  it("送る処理が失敗しても、呼び出し口は投げない（元の Callable・トリガーを失敗させない）", async () => {
    const roomId = "notify-failure";
    await addRoom(roomId, { status: "unlocked", ready: MEMBERS });
    const failing = { db, sender: () => Promise.reject(new Error("FCM に繋がらない")) };

    await expect(sendRoomUnlocked(failing, `${roomId}-other`)).resolves.toEqual({ kind: "skipped", reason: "room-not-found" });
    await expect(notifyRoomUnlocked(failing, roomId, "forced")).resolves.toBeUndefined();
  });
});
