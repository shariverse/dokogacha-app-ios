/**
 * ルームの終了（05 の §5 の `closeRoom`・`autoCloseRooms`・02 の §6.5 F-44）と、終了したときの過去のアイデア（F-13）を Emulator で確かめる。
 * - `closeRoom`・自動の終了（`closeOverdueRooms`。スケジュールの中身）を Admin SDK で直接呼ぶこと
 * - Functions の Emulator で動くトリガー（`onRoomClosed`）が、`closed` になったルームの当選以外の候補を各メンバーの過去のアイデアにすること
 *   （トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る）
 *
 * ルームは `set` で作る（作成ではトリガーが動かない）。メンバーのドキュメントは入れない（過去のアイデアの宛先は `memberIds`）。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `close-` を付ける。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { closeOverdueRooms, closeRoom, registerPastIdeas, autoCloseRoom } from "../../functions/src/close/service";
import { AUTO_CLOSE_AFTER_DRAW_MS } from "../../functions/src/domain/constants";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;
/** 1 日のミリ秒 */
const DAY_MS = 86_400_000;

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

describe("ルームの終了（closeRoom・autoCloseRooms・onRoomClosed）", () => {
  let app: App;
  let db: Firestore;

  /** 外部のもの（今の時刻は実際の時刻） */
  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
  }

  /**
   * 行き先が決まったルームを作る（alice が作成者・bob・carol がメンバー。c1 のサンシャイン水族館が当選、c2・c3 は外れ。
   * c3 は引き直しで外れた前の当選）。
   */
  async function addRoom(
    roomId: string,
    options: { status?: string; drawnAt?: Timestamp | null; members?: string[] } = {},
  ): Promise<void> {
    const status = options.status ?? "drawn";
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: "alice",
      inviteCode: "CL0SE1",
      status,
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
      forcedUnlock: false,
      memberIds: options.members ?? ["alice", "bob", "carol"],
      memberCount: 3,
      readyCount: 3,
      candidateCount: 3,
      adFreeSponsor: null,
      currentDrawId: status === "open" ? null : "d2",
      winnerCandidateId: status === "open" ? null : "c1",
      excludedCandidateIds: ["c3"],
      reroll: { used: true, votesFor: ["alice", "bob"], votesAgainst: [], status: "passed" },
      createdAt: Timestamp.fromMillis(Date.now() - 10 * DAY_MS),
      drawnAt: options.drawnAt === undefined ? Timestamp.now() : options.drawnAt,
      closedAt: null,
    });
    const candidates: [string, string, string, string[]][] = [
      ["c1", "サンシャイン水族館", "aquarium", ["bob"]],
      ["c2", "江の島", "sea", ["alice", "bob", "carol"]],
      ["c3", "明治神宮", "shrine", []],
    ];
    for (const [id, name, category, likedBy] of candidates) {
      await db.doc(`rooms/${roomId}/candidates/${id}`).set({
        place: { name, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
        category,
        note: "",
        url: null,
        postedBy: "bob",
        postedByName: "bob",
        colorIndex: 0,
        likedBy,
        fromPastIdeaId: null,
        createdAt: Timestamp.now(),
      });
    }
  }

  /** ルームのドキュメントの値 */
  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  /**
   * `roomId` のルームから登録された過去のアイデア（ID → 値）。
   * 前のテストのトリガーが `clearFirestore` の後に遅れて書くことがあるので、ほかのルームのものは見ない
   */
  async function pastIdeas(uid: string, roomId: string): Promise<Record<string, FirebaseFirestore.DocumentData>> {
    const snapshot = await db.collection(`users/${uid}/pastIdeas`).where("sourceRoomId", "==", roomId).get();
    return Object.fromEntries(snapshot.docs.map((doc) => [doc.id, doc.data()]));
  }

  /**
   * `uid` の過去のアイデアの ID が `expected` になるまで読み直す。`TRIGGER_TIMEOUT_MS` を過ぎたら失敗する
   * （固定の時間で待たずに、トリガーが書き終えた時点で次へ進む）
   */
  async function waitForPastIdeas(
    uid: string,
    roomId: string,
    expected: string[],
  ): Promise<Record<string, FirebaseFirestore.DocumentData>> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    let last: Record<string, FirebaseFirestore.DocumentData> = {};
    while (Date.now() < deadline) {
      last = await pastIdeas(uid, roomId);
      if (JSON.stringify(Object.keys(last).sort()) === JSON.stringify([...expected].sort())) {
        return last;
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${uid} の過去のアイデアが ${JSON.stringify(expected)} にならない（最後: ${JSON.stringify(Object.keys(last))}）`);
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("close"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("closeRoom（作成者の「この行き先で決定」）", () => {
    it("作成者が drawn のルームを closed にし、トリガーが当選以外の候補を全員の過去のアイデアにする", async () => {
      await addRoom("close-owner");
      await expect(closeRoom(deps(), "alice", { roomId: "close-owner" })).resolves.toEqual({});

      const room = await roomData("close-owner");
      expect(room.status).toBe("closed");
      expect(room.closedAt).toBeInstanceOf(Timestamp);

      const ideas = await waitForPastIdeas("bob", "close-owner", ["close-owner_c2", "close-owner_c3"]);
      expect(ideas["close-owner_c2"]).toEqual({
        sourceRoomId: "close-owner",
        sourceRoomName: "年末の旅行",
        sourceClosedAt: room.closedAt as Timestamp,
        sourceWinnerName: "サンシャイン水族館",
        place: { name: "江の島", area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
        category: "sea",
        prevLikeCount: 3,
      });
      // 引き直しで外れた前の当選（c3）も「外れた候補」に入る（02 の §3.4）
      expect(ideas["close-owner_c3"]?.prevLikeCount).toBe(0);
      await waitForPastIdeas("alice", "close-owner", ["close-owner_c2", "close-owner_c3"]);
      await waitForPastIdeas("carol", "close-owner", ["close-owner_c2", "close-owner_c3"]);
    });

    it("もう closed なら何も書かずに成功する（closedAt を書き換えない）", async () => {
      await addRoom("close-twice");
      await closeRoom(deps(), "alice", { roomId: "close-twice" });
      const first = (await roomData("close-twice")).closedAt as Timestamp;
      await expect(closeRoom(deps(), "alice", { roomId: "close-twice" })).resolves.toEqual({});
      expect(((await roomData("close-twice")).closedAt as Timestamp).isEqual(first)).toBe(true);
    });

    it("同時に 2 回呼んでも、どちらも成功してルームは 1 回だけ終了する", async () => {
      await addRoom("close-race");
      await expect(
        Promise.all([
          closeRoom(deps(), "alice", { roomId: "close-race" }),
          closeRoom(deps(), "alice", { roomId: "close-race" }),
        ]),
      ).resolves.toEqual([{}, {}]);
      expect((await roomData("close-race")).status).toBe("closed");
      await waitForPastIdeas("bob", "close-race", ["close-race_c2", "close-race_c3"]);
    });

    it("作成者以外は not-room-owner・メンバー以外は not-room-member（ルームは drawn のまま）", async () => {
      await addRoom("close-denied");
      await expectReason(closeRoom(deps(), "bob", { roomId: "close-denied" }), "permission-denied", "not-room-owner");
      await expectReason(closeRoom(deps(), "dave", { roomId: "close-denied" }), "permission-denied", "not-room-member");
      expect((await roomData("close-denied")).status).toBe("drawn");
    });

    it("行き先が決まる前は room-not-drawn・無いルームは room-not-found・入力が壊れていれば invalid-argument", async () => {
      await addRoom("close-open", { status: "open", drawnAt: null });
      await expectReason(closeRoom(deps(), "alice", { roomId: "close-open" }), "failed-precondition", "room-not-drawn");
      expect((await roomData("close-open")).status).toBe("open");
      await expectReason(closeRoom(deps(), "alice", { roomId: "close-missing" }), "not-found", "room-not-found");
      await expectReason(closeRoom(deps(), "alice", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
    });
  });

  describe("autoCloseRooms（抽選から 7 日）", () => {
    it("抽選から 7 日たった drawn だけを closed にし、トリガーが過去のアイデアを登録する", async () => {
      const now = Date.now();
      await addRoom("close-auto-old", { drawnAt: Timestamp.fromMillis(now - AUTO_CLOSE_AFTER_DRAW_MS - 1_000) });
      await addRoom("close-auto-new", { drawnAt: Timestamp.fromMillis(now - AUTO_CLOSE_AFTER_DRAW_MS + 60_000) });
      await addRoom("close-auto-open", { status: "open", drawnAt: null });

      const result = await closeOverdueRooms({ db, nowMs: () => now });
      expect(result).toEqual({ rooms: 1, closed: 1 });
      expect((await roomData("close-auto-old")).status).toBe("closed");
      expect((await roomData("close-auto-new")).status).toBe("drawn");
      expect((await roomData("close-auto-open")).status).toBe("open");
      await waitForPastIdeas("carol", "close-auto-old", ["close-auto-old_c2", "close-auto-old_c3"]);
    });

    it("見つけた後に作成者が決定していたら書かない（読み直して確かめる）", async () => {
      await addRoom("close-auto-raced", { drawnAt: Timestamp.fromMillis(Date.now() - 8 * DAY_MS) });
      await closeRoom(deps(), "alice", { roomId: "close-auto-raced" });
      const closedAt = (await roomData("close-auto-raced")).closedAt as Timestamp;
      await expect(autoCloseRoom(deps(), "close-auto-raced")).resolves.toBe(false);
      await expect(autoCloseRoom(deps(), "close-auto-none")).resolves.toBe(false);
      expect(((await roomData("close-auto-raced")).closedAt as Timestamp).isEqual(closedAt)).toBe(true);
    });
  });

  describe("registerPastIdeas（onRoomClosed の中身）", () => {
    it("何度呼んでも同じ過去のアイデアになる（冪等）・終了したときのメンバーだけに登録する", async () => {
      await addRoom("close-idempotent", { members: ["alice", "bob"] });
      await closeRoom(deps(), "alice", { roomId: "close-idempotent" });
      const expected = ["close-idempotent_c2", "close-idempotent_c3"];
      const first = await waitForPastIdeas("alice", "close-idempotent", expected);

      await expect(registerPastIdeas(db, "close-idempotent")).resolves.toBe(4);
      await expect(registerPastIdeas(db, "close-idempotent")).resolves.toBe(4);
      expect(await pastIdeas("alice", "close-idempotent")).toEqual(first);
      expect(Object.keys(await pastIdeas("bob", "close-idempotent")).sort()).toEqual(expected);
      expect(await pastIdeas("carol", "close-idempotent")).toEqual({});
    });

    it("closed でないルーム・無いルームには何も登録しない", async () => {
      await addRoom("close-not-closed");
      await expect(registerPastIdeas(db, "close-not-closed")).resolves.toBe(0);
      await expect(registerPastIdeas(db, "close-nothing")).resolves.toBe(0);
      expect(await pastIdeas("bob", "close-not-closed")).toEqual({});
    });
  });
});
