/**
 * ルーム設定の変更（05 の §5 の `updateRoomSettings`・02 の F-03 の変更ルール）を、Emulator の Firestore に対して直接呼んで確かめる。
 * 変更ルールの細かいケースは `functions/src/settings/logic.test.ts`、ここでは書き込みと解禁の判定し直しを確かめる。
 *
 * メンバーのドキュメントを書くとトリガー（onMemberWrite）も動くので、ルームの数と状態はトリガーが数え直した後に操作を始める。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `settings-` を付ける。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { updateRoomSettings } from "../../functions/src/settings/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限 */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;
/** 1 時間のミリ秒 */
const HOUR_MS = 3_600_000;

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

describe("ルーム設定の変更（updateRoomSettings）", () => {
  let app: App;
  let db: Firestore;

  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
  }

  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  /** ルームの数がトリガーの数え直した値になるまで待つ */
  async function waitForCounts(roomId: string, memberCount: number, readyCount: number): Promise<void> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const room = await roomData(roomId);
      if (room.memberCount === memberCount && room.readyCount === readyCount) {
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても数え直されない`);
  }

  /** alice が作成者・bob と carol がメンバーのルーム（`ready` の人は準備OK） */
  async function addRoom(
    roomId: string,
    options: { status?: string; ready?: string[]; unlockRule?: string; deadlineAt?: Timestamp | null } = {},
  ): Promise<string> {
    const members = ["alice", "bob", "carol"];
    const ready = new Set(options.ready ?? []);
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: "alice",
      inviteCode: "ABCDEF",
      status: options.status ?? "open",
      settings: {
        postLimit: 3,
        unlockRule: options.unlockRule ?? "all",
        deadlineAt: options.deadlineAt ?? null,
        likeMode: "boost",
      },
      forcedUnlock: false,
      memberIds: members,
      memberCount: -1,
      readyCount: -1,
      candidateCount: 0,
      adFreeSponsor: null,
      excludedCandidateIds: [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
      createdAt: Timestamp.now(),
    });
    for (const [index, uid] of members.entries()) {
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: uid,
        avatarColor: AVATAR_COLORS[0],
        role: index === 0 ? "owner" : "member",
        ready: ready.has(uid),
        joinedAt: Timestamp.now(),
        lastSeenAt: Timestamp.now(),
      });
    }
    await waitForCounts(roomId, members.length, ready.size);
    return roomId;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("settings"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("作成者は open のルームのすべての項目を変えられる（アプリの JSON の形。締切日時は Timestamp で保存する）", async () => {
    const roomId = await addRoom("settings-all");
    const deadlineAt = Date.now() + 2 * HOUR_MS;
    await expect(
      updateRoomSettings(deps(), "alice", {
        roomId,
        name: " 春の旅行 ",
        postLimit: 5,
        unlockRule: "deadline",
        deadlineAt,
        likeMode: "equal",
      }),
    ).resolves.toEqual({});
    const room = await roomData(roomId);
    expect(room).toMatchObject({
      name: "春の旅行",
      status: "open",
      settings: { postLimit: 5, unlockRule: "deadline", likeMode: "equal" },
    });
    expect((room.settings as { deadlineAt: Timestamp }).deadlineAt.toMillis()).toBe(deadlineAt);

    // 締切日時から全員OKに戻すと、締切日時を消す
    await updateRoomSettings(deps(), "alice", { roomId, unlockRule: "all" });
    expect((await roomData(roomId)).settings).toMatchObject({ unlockRule: "all", deadlineAt: null });
  });

  it("送った項目だけを変え、ほかの設定は残す", async () => {
    const roomId = await addRoom("settings-partial");
    await updateRoomSettings(deps(), "alice", { roomId, likeMode: "equal" });
    expect(await roomData(roomId)).toMatchObject({
      name: "年末の旅行",
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "equal" },
    });
  });

  it("条件を変えたら解禁を判定し直す（全員OK → 過半数OK で、すでに過半数が準備OKなら unlocked）", async () => {
    const roomId = await addRoom("settings-rejudge", { ready: ["alice", "bob"] });
    expect((await roomData(roomId)).status).toBe("open");
    await updateRoomSettings(deps(), "alice", { roomId, unlockRule: "majority" });
    expect(await roomData(roomId)).toMatchObject({ status: "unlocked", readyCount: 2, settings: { unlockRule: "majority" } });
  });

  it("条件を締切日時にしても、締切の前なら open のまま", async () => {
    const roomId = await addRoom("settings-deadline", { ready: ["alice", "bob", "carol"] });
    // 全員OKで解禁しているので、条件を変えられない（open のときだけ）
    await expectReason(
      updateRoomSettings(deps(), "alice", { roomId, unlockRule: "deadline", deadlineAt: Date.now() + 2 * HOUR_MS }),
      "failed-precondition",
      "unlock-rule-locked",
    );
    const openRoomId = await addRoom("settings-deadline-open", { ready: ["alice"] });
    await updateRoomSettings(deps(), "alice", {
      roomId: openRoomId,
      unlockRule: "deadline",
      deadlineAt: Date.now() + 2 * HOUR_MS,
    });
    expect((await roomData(openRoomId)).status).toBe("open");
  });

  it("作成者以外は変えられない", async () => {
    const roomId = await addRoom("settings-owner");
    await expectReason(updateRoomSettings(deps(), "bob", { roomId, name: "乗っ取り" }), "permission-denied", "not-room-owner");
    expect((await roomData(roomId)).name).toBe("年末の旅行");
  });

  it("投稿数は引き上げのみ", async () => {
    const roomId = await addRoom("settings-post");
    await expectReason(updateRoomSettings(deps(), "alice", { roomId, postLimit: 2 }), "failed-precondition", "post-limit-decrease");
    await updateRoomSettings(deps(), "alice", { roomId, postLimit: 4 });
    expect((await roomData(roomId)).settings).toMatchObject({ postLimit: 4 });
  });

  it("unlocked ではルーム名・投稿数・いいねの効き方を変えられ、解禁の条件は変えられない", async () => {
    const roomId = await addRoom("settings-unlocked", { ready: ["alice", "bob", "carol"] });
    expect((await roomData(roomId)).status).toBe("unlocked");
    await updateRoomSettings(deps(), "alice", { roomId, name: "春", postLimit: 4, likeMode: "equal" });
    expect(await roomData(roomId)).toMatchObject({
      name: "春",
      status: "unlocked",
      settings: { postLimit: 4, likeMode: "equal", unlockRule: "all" },
    });
    await expectReason(
      updateRoomSettings(deps(), "alice", { roomId, unlockRule: "majority" }),
      "failed-precondition",
      "unlock-rule-locked",
    );
  });

  it("drawn ではルーム名と投稿数だけを変えられる", async () => {
    const roomId = await addRoom("settings-drawn", { status: "drawn" });
    await updateRoomSettings(deps(), "alice", { roomId, name: "春", postLimit: 4 });
    expect(await roomData(roomId)).toMatchObject({ name: "春", status: "drawn", settings: { postLimit: 4 } });
    await expectReason(
      updateRoomSettings(deps(), "alice", { roomId, likeMode: "equal" }),
      "failed-precondition",
      "like-mode-locked",
    );
    await expectReason(
      updateRoomSettings(deps(), "alice", { roomId, unlockRule: "majority" }),
      "failed-precondition",
      "unlock-rule-locked",
    );
  });

  it("closed では何も変えられない", async () => {
    const roomId = await addRoom("settings-closed", { status: "closed" });
    await expectReason(updateRoomSettings(deps(), "alice", { roomId, name: "春" }), "failed-precondition", "room-closed");
    expect((await roomData(roomId)).name).toBe("年末の旅行");
  });

  it("ルームが無い・入力が正しくない", async () => {
    await expectReason(updateRoomSettings(deps(), "alice", { roomId: "settings-none", name: "春" }), "not-found", "room-not-found");
    await expectReason(updateRoomSettings(deps(), "alice", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
    const roomId = await addRoom("settings-invalid");
    await expectReason(
      updateRoomSettings(deps(), "alice", { roomId, unlockRule: "deadline", deadlineAt: Date.now() + 10 * 60_000 }),
      "invalid-argument",
      "invalid-argument",
    );
    expect((await roomData(roomId)).settings).toMatchObject({ unlockRule: "all", deadlineAt: null });
  });
});
