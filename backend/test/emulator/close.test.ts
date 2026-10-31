/**
 * ルームの終了（05 の §5 の `closeRoom`・`autoCloseRooms`・02 の §6.5 F-44）と、終了したときの過去のアイデア（F-13）を Emulator で確かめる。
 * - `closeRoom`（「この行き先で決定」の `decide`・途中の終了の `endEarly`）・自動の終了（`closeOverdueRooms`。スケジュールの中身）を Admin SDK で直接呼ぶこと
 * - Functions の Emulator で動くトリガー（`onRoomClosed`）が、`closed` になったルームの当選以外の候補を各メンバーの過去のアイデアにすること
 *   （トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る）
 *
 * ルームは `set` で作る（作成ではトリガーが動かない）。メンバーのドキュメントは入れない（過去のアイデアの宛先は `memberIds`）。
 * 過去のアイデアは `users/{uid}` がある人にだけ登録するので、メンバーのプロフィールは置く。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `close-` を付ける。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { closeOverdueRooms, closeRoom, registerPastIdeas, autoCloseRoom } from "../../functions/src/close/service";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { AUTO_CLOSE_AFTER_DRAW_MS } from "../../functions/src/domain/constants";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import { expireRerolls } from "../../functions/src/reroll/service";
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
    options: { status?: string; drawnAt?: Timestamp | null; members?: string[]; reroll?: Record<string, unknown> } = {},
  ): Promise<void> {
    const status = options.status ?? "drawn";
    // 過去のアイデアは users/{uid} がある人にだけ登録する（アカウントを削除した人を飛ばす）ので、メンバーのプロフィールを置く
    for (const uid of ["alice", "bob", "carol"]) {
      await db.doc(`users/${uid}`).set({ displayName: uid, avatarColor: AVATAR_COLORS[0], adFree: false, fcmTokens: [], createdAt: Timestamp.now() });
    }
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
      reroll: options.reroll ?? { used: true, votesFor: ["alice", "bob"], votesAgainst: [], status: "passed" },
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

    it("引き直しの投票中でも終了でき、同じ書き込みで投票を否決にする（expireRerolls が後で終了したルームを拾わない）", async () => {
      const proposedAt = Timestamp.now();
      await addRoom("close-voting", {
        reroll: { used: true, proposedBy: "bob", proposedAt, votesFor: ["bob"], votesAgainst: [], status: "voting" },
      });
      await expect(closeRoom(deps(), "alice", { roomId: "close-voting" })).resolves.toEqual({});

      const room = await roomData("close-voting");
      expect(room.status).toBe("closed");
      expect(room.reroll).toEqual({ used: true, proposedBy: "bob", proposedAt, votesFor: ["bob"], votesAgainst: [], status: "rejected" });
      // 提案から 24 時間を過ぎても、期限の判定は終了したルームを見つけない（書き込まない）
      await expect(expireRerolls({ db, nowMs: () => Date.now() + 2 * DAY_MS })).resolves.toEqual({ rooms: 0, rejected: 0, passed: 0 });
      expect((await roomData("close-voting")).reroll).toEqual(room.reroll);
      await waitForPastIdeas("bob", "close-voting", ["close-voting_c2", "close-voting_c3"]);
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

  describe("closeRoom の endEarly（S-12 の「ルームを終了する」。抽選の前に途中で終了する）", () => {
    it("作成者が open・unlocked のルームを closed にする", async () => {
      await addRoom("close-early-open", { status: "open", drawnAt: null, reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" } });
      await addRoom("close-early-unlocked", { status: "unlocked", drawnAt: null });
      for (const roomId of ["close-early-open", "close-early-unlocked"]) {
        await expect(closeRoom(deps(), "alice", { roomId, reason: "endEarly" })).resolves.toEqual({});
        const room = await roomData(roomId);
        expect(room.status).toBe("closed");
        expect(room.closedAt).toBeInstanceOf(Timestamp);
      }
    });

    it("確認の間にほかの人がガチャを回して drawn になっていたら room-already-decided（drawn のまま。決定と同じ終了にしない）", async () => {
      await addRoom("close-early-drawn");
      await expectReason(
        closeRoom(deps(), "alice", { roomId: "close-early-drawn", reason: "endEarly" }),
        "failed-precondition",
        "room-already-decided",
      );
      const room = await roomData("close-early-drawn");
      expect(room.status).toBe("drawn");
      expect(room.closedAt).toBeNull();
    });

    it("もう closed なら何も書かずに成功する（closedAt を書き換えない）", async () => {
      await addRoom("close-early-twice", { status: "open", drawnAt: null });
      await closeRoom(deps(), "alice", { roomId: "close-early-twice", reason: "endEarly" });
      const first = (await roomData("close-early-twice")).closedAt as Timestamp;
      await expect(closeRoom(deps(), "alice", { roomId: "close-early-twice", reason: "endEarly" })).resolves.toEqual({});
      await expect(closeRoom(deps(), "alice", { roomId: "close-early-twice", reason: "decide" })).resolves.toEqual({});
      expect(((await roomData("close-early-twice")).closedAt as Timestamp).isEqual(first)).toBe(true);
    });

    it("作成者以外は not-room-owner・メンバー以外は not-room-member・意図が知らない値なら invalid-argument（ルームは open のまま）", async () => {
      await addRoom("close-early-denied", { status: "open", drawnAt: null });
      await expectReason(
        closeRoom(deps(), "bob", { roomId: "close-early-denied", reason: "endEarly" }),
        "permission-denied",
        "not-room-owner",
      );
      await expectReason(
        closeRoom(deps(), "dave", { roomId: "close-early-denied", reason: "endEarly" }),
        "permission-denied",
        "not-room-member",
      );
      await expectReason(
        closeRoom(deps(), "alice", { roomId: "close-early-denied", reason: "abandon" }),
        "invalid-argument",
        "invalid-argument",
      );
      expect((await roomData("close-early-denied")).status).toBe("open");
    });

    it("意図が decide なら open は room-not-drawn のまま（意図を送らない前の版のアプリと同じ）", async () => {
      await addRoom("close-early-decide", { status: "open", drawnAt: null });
      await expectReason(
        closeRoom(deps(), "alice", { roomId: "close-early-decide", reason: "decide" }),
        "failed-precondition",
        "room-not-drawn",
      );
      expect((await roomData("close-early-decide")).status).toBe("open");
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

    it("引き直しの投票中に 7 日たったら、終了と同じ書き込みで投票を否決にする", async () => {
      const now = Date.now();
      await addRoom("close-auto-voting", {
        drawnAt: Timestamp.fromMillis(now - AUTO_CLOSE_AFTER_DRAW_MS - 1_000),
        reroll: { used: true, proposedBy: "bob", proposedAt: Timestamp.fromMillis(now - 1_000), votesFor: ["bob"], votesAgainst: [], status: "voting" },
      });
      await expect(closeOverdueRooms({ db, nowMs: () => now })).resolves.toEqual({ rooms: 1, closed: 1 });
      const room = await roomData("close-auto-voting");
      expect(room.status).toBe("closed");
      expect((room.reroll as { status: string }).status).toBe("rejected");
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

    it("終了した時点のルームの値を渡すと、その後に退出した人にも登録する（トリガーの event.data.after）", async () => {
      // 作成（set）ではトリガーが動かないので、closed のルームを直接作り、終了した時点の値を控える
      await addRoom("close-snapshot", { status: "closed" });
      const closedRoom = await roomData("close-snapshot");
      // 終了の直後、トリガーが動く前に carol が退出した（closed のままの更新なので、トリガーは何もしない）
      await db.doc("rooms/close-snapshot").update({ memberIds: ["alice", "bob"], memberCount: 2 });

      await expect(registerPastIdeas(db, "close-snapshot", closedRoom)).resolves.toBe(6);
      const expected = ["close-snapshot_c2", "close-snapshot_c3"];
      expect(Object.keys(await pastIdeas("carol", "close-snapshot")).sort()).toEqual(expected);
      expect(Object.keys(await pastIdeas("alice", "close-snapshot")).sort()).toEqual(expected);
      expect((await pastIdeas("carol", "close-snapshot"))["close-snapshot_c2"]).toMatchObject({
        sourceRoomName: "年末の旅行",
        prevLikeCount: 3,
      });
    });

    it("終了した時点の値を渡さないときは読み直す（読み直した時点のメンバーにだけ登録する）", async () => {
      await addRoom("close-reread", { status: "closed" });
      await db.doc("rooms/close-reread").update({ memberIds: ["alice", "bob"], memberCount: 2 });

      await expect(registerPastIdeas(db, "close-reread")).resolves.toBe(4);
      expect(await pastIdeas("carol", "close-reread")).toEqual({});
    });

    it("アカウントを削除した人（users/{uid} が無い）には、終了した時点のメンバーでも登録しない（F-06）", async () => {
      await addRoom("close-deleted", { status: "closed" });
      const closedRoom = await roomData("close-deleted");
      // 終了の直後、トリガーが動く前に carol がアカウントを削除した（users/{uid} と過去のアイデアを消した）
      await db.doc("users/carol").delete();

      await expect(registerPastIdeas(db, "close-deleted", closedRoom)).resolves.toBe(4);
      const expected = ["close-deleted_c2", "close-deleted_c3"];
      expect(Object.keys(await pastIdeas("alice", "close-deleted")).sort()).toEqual(expected);
      expect(Object.keys(await pastIdeas("bob", "close-deleted")).sort()).toEqual(expected);
      expect(await pastIdeas("carol", "close-deleted")).toEqual({});
      expect((await db.doc("users/carol").get()).exists).toBe(false);
    });

    it("closed でないルーム・無いルームには何も登録しない", async () => {
      await addRoom("close-not-closed");
      await expect(registerPastIdeas(db, "close-not-closed")).resolves.toBe(0);
      await expect(registerPastIdeas(db, "close-nothing")).resolves.toBe(0);
      expect(await pastIdeas("bob", "close-not-closed")).toEqual({});
    });
  });
});
