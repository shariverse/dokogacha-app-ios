/**
 * 準備OKと解禁（05 の §5 の `onMemberWrite`・`forceUnlock`・`checkDeadlines`・02 の F-30〜32）を Emulator で確かめる。
 * - Functions の Emulator で動くトリガー（`onMemberWrite`）が、メンバーの書き込みから数え直して `open`⇄`unlocked` にすること
 *   （トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る）
 * - `forceUnlock`・締切日時の判定（`unlockPassedDeadlines`。スケジュールの中身）を Admin SDK で直接呼ぶこと
 *
 * メンバーのドキュメントを書くとトリガーも動くので、直接呼ぶテストでも、結果はトリガーと重なっても同じになる値（最終の状態）で確かめる。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `unlock-` を付ける。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { joinRoom, leaveRoom, removeMember } from "../../functions/src/rooms/service";
import { forceUnlock, recountRoom, unlockPassedDeadlines } from "../../functions/src/unlock/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;
/** 1 時間のミリ秒 */
const HOUR_MS = 3_600_000;

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

describe("準備OKと解禁（onMemberWrite・forceUnlock・checkDeadlines）", () => {
  let app: App;
  let db: Firestore;

  /** 外部のもの（今の時刻は実際の時刻。トリガーも実際の時刻で判定するので、ずらすと結果が食い違う） */
  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
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
   * ルームの値が `expected` を満たすまで、`POLL_INTERVAL_MS` ごとに読み直す。`TRIGGER_TIMEOUT_MS` を過ぎたら失敗する。
   * 固定の時間で待たずに、反映が済んだ時点で次へ進む。
   */
  async function waitForRoom(roomId: string, expected: Record<string, unknown>): Promise<void> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    let last: Record<string, unknown> = {};
    while (Date.now() < deadline) {
      const data = await roomData(roomId);
      last = Object.fromEntries(Object.keys(expected).map((key) => [key, data[key] as unknown]));
      if (Object.entries(expected).every(([key, value]) => last[key] === value)) {
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    throw new Error(
      `${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${JSON.stringify(expected)} にならない（最後: ${JSON.stringify(last)}）`,
    );
  }

  /** プロフィールを作る（joinRoom で参加させる人） */
  async function addUser(uid: string): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: uid,
      avatarColor: AVATAR_COLORS[0],
      adFree: false,
      fcmTokens: [],
      createdAt: Timestamp.now(),
    });
  }

  /**
   * ルームを作る。先頭の人が作成者で、`ready` の人は準備OK。招待コード（既定は `ABCDEF`）で参加できる。
   * `memberCount`・`readyCount` は、トリガーが数え直したと分かるように -1 で作り、数え直した値になるまで待つ
   * （トリガーが一度はすべてのメンバーを読んだ後に、テストの操作を始める）。
   */
  async function addRoom(
    roomId: string,
    options: {
      members?: string[];
      ready?: string[];
      unlockRule?: string;
      deadlineAt?: Timestamp | null;
      status?: string;
      forcedUnlock?: boolean;
      rerollStatus?: string;
      inviteCode?: string;
    } = {},
  ): Promise<{ roomId: string; inviteCode: string }> {
    const members = options.members ?? ["alice", "bob", "carol"];
    const ready = new Set(options.ready ?? []);
    const inviteCode = options.inviteCode ?? "ABCDEF";
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: members[0],
      inviteCode,
      status: options.status ?? "open",
      settings: {
        postLimit: 3,
        unlockRule: options.unlockRule ?? "all",
        deadlineAt: options.deadlineAt ?? null,
        likeMode: "boost",
      },
      forcedUnlock: options.forcedUnlock ?? false,
      memberIds: members,
      memberCount: -1,
      readyCount: -1,
      candidateCount: 0,
      adFreeSponsor: null,
      excludedCandidateIds: [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: options.rerollStatus ?? "none" },
      createdAt: Timestamp.now(),
    });
    await db.doc(`inviteCodes/${inviteCode}`).set({ roomId, createdAt: Timestamp.now() });
    for (const [index, uid] of members.entries()) {
      await addUser(uid);
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: uid,
        avatarColor: AVATAR_COLORS[0],
        role: index === 0 ? "owner" : "member",
        ready: ready.has(uid),
        joinedAt: Timestamp.fromMillis(Date.now() + index),
        lastSeenAt: Timestamp.now(),
      });
    }
    await waitForRoom(roomId, { memberCount: members.length, readyCount: ready.size });
    return { roomId, inviteCode };
  }

  /** メンバーの準備OKを変える（アプリの直接の書き込みと同じ。トリガーが動く） */
  async function setReady(roomId: string, uid: string, ready: boolean): Promise<void> {
    await db.doc(`rooms/${roomId}/members/${uid}`).update({ ready });
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("unlock"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("onMemberWrite（Functions の Emulator のトリガー）", () => {
    it(
      "全員OK条件で最後の 1 人が準備OKすると unlocked になり、誰かが取り消すと open に戻る（02 の F-30〜32 の AC）",
      async () => {
        const { roomId } = await addRoom("unlock-all", { ready: ["alice", "bob"] });
        expect((await roomData(roomId)).status).toBe("open");

        await setReady(roomId, "carol", true);
        await waitForRoom(roomId, { readyCount: 3, status: "unlocked" });

        await setReady(roomId, "bob", false);
        await waitForRoom(roomId, { readyCount: 2, status: "open" });
      },
      TRIGGER_TIMEOUT_MS * 4,
    );

    it(
      "過半数OK条件で過半数が準備OKすると unlocked、過半数を割ると open に戻る",
      async () => {
        const { roomId } = await addRoom("unlock-majority", {
          members: ["alice", "bob", "carol", "dave", "erin"],
          ready: ["alice", "bob"],
          unlockRule: "majority",
        });
        await setReady(roomId, "carol", true);
        await waitForRoom(roomId, { readyCount: 3, status: "unlocked" });
        await setReady(roomId, "dave", true);
        await waitForRoom(roomId, { readyCount: 4, status: "unlocked" });
        await setReady(roomId, "dave", false);
        await setReady(roomId, "carol", false);
        await waitForRoom(roomId, { readyCount: 2, status: "open" });
      },
      TRIGGER_TIMEOUT_MS * 5,
    );

    it(
      "準備OKの人が退出・削除されたら readyCount を数え直す（退出の Callable は数を減らさない）",
      async () => {
        const { roomId } = await addRoom("unlock-leave", {
          members: ["alice", "bob", "carol", "dave"],
          ready: ["bob", "carol"],
        });
        await leaveRoom(deps(), "bob", { roomId });
        await waitForRoom(roomId, { memberCount: 3, readyCount: 1, status: "open" });

        // 準備OKでない人が抜けて、残りが全員準備OKになると解禁する
        await setReady(roomId, "alice", true);
        await waitForRoom(roomId, { readyCount: 2 });
        await removeMember(deps(), "alice", { roomId, memberId: "dave" });
        await waitForRoom(roomId, { memberCount: 2, readyCount: 2, status: "unlocked" });
      },
      TRIGGER_TIMEOUT_MS * 4,
    );

    it(
      "解禁済みのルームに新しい人が参加すると open に戻る（02 の F-04「解禁条件を再計算する」）",
      async () => {
        const { roomId, inviteCode } = await addRoom("unlock-join", {
          members: ["alice", "bob"],
          ready: ["alice", "bob"],
          inviteCode: "HN48PX",
        });
        await waitForRoom(roomId, { status: "unlocked" });
        await addUser("carol");
        await joinRoom(deps(), "carol", { inviteCode });
        await waitForRoom(roomId, { memberCount: 3, readyCount: 2, status: "open" });
      },
      TRIGGER_TIMEOUT_MS * 3,
    );

    it(
      "強制解禁したルームは、取り消し・参加があっても unlocked のまま",
      async () => {
        const { roomId, inviteCode } = await addRoom("unlock-forced", { ready: ["bob"], inviteCode: "MR36TW" });
        await forceUnlock(deps(), "alice", { roomId });
        expect(await roomData(roomId)).toMatchObject({ status: "unlocked", forcedUnlock: true });

        await setReady(roomId, "bob", false);
        await waitForRoom(roomId, { readyCount: 0, status: "unlocked" });
        // joinRoom は memberCount を自分で 4 にするので、memberCount だけを待つとトリガーが数え直す前に通ってしまう。
        // readyCount をトリガーしか直さない値にずらしてから参加させ、数え直した後（readyCount が 0 に戻った後）の状態を確かめる
        await db.doc(`rooms/${roomId}`).update({ readyCount: 99 });
        await addUser("dave");
        await joinRoom(deps(), "dave", { inviteCode });
        await waitForRoom(roomId, { memberCount: 4, readyCount: 0, status: "unlocked" });
      },
      TRIGGER_TIMEOUT_MS * 3,
    );

    it(
      "引き直しが可決して unlocked に戻ったルームは、取り消しても open に戻さない（02 の §6.4「準備OKはやり直さない」）",
      async () => {
        const { roomId } = await addRoom("unlock-reroll", {
          status: "unlocked",
          ready: ["alice", "bob", "carol"],
          rerollStatus: "passed",
        });
        await setReady(roomId, "carol", false);
        await waitForRoom(roomId, { readyCount: 2, status: "unlocked" });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "drawn のルームは数だけ数え直し、状態を変えない",
      async () => {
        const { roomId } = await addRoom("unlock-drawn", { status: "drawn", ready: ["alice", "bob", "carol"] });
        expect((await roomData(roomId)).status).toBe("drawn");
        await db.doc(`rooms/${roomId}`).update({ readyCount: 99 });
        // drawn では準備OKをルールで書けないが、Admin SDK でメンバーを消すとトリガーが動く
        await db.doc(`rooms/${roomId}/members/carol`).delete();
        await waitForRoom(roomId, { memberCount: 2, readyCount: 2, status: "drawn" });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );
  });

  describe("recountRoom（onMemberWrite の中身を直接呼ぶ）", () => {
    it("数え直した値と状態を書き、2 回目は何も書かない（冪等）", async () => {
      const { roomId } = await addRoom("unlock-direct", { ready: ["alice", "bob", "carol"] });
      await waitForRoom(roomId, { status: "unlocked" });
      // 数のフィールドを壊しても、数え直して直す
      await db.doc(`rooms/${roomId}`).update({ readyCount: 0, memberCount: 7 });
      await recountRoom(deps(), roomId);
      expect(await roomData(roomId)).toMatchObject({ memberCount: 3, readyCount: 3, status: "unlocked" });
      await expect(recountRoom(deps(), roomId)).resolves.toEqual({ changed: false, unlockedBy: null });
    });

    it("ルームが無ければ何もしない（ルームを作り直さない）", async () => {
      await expect(recountRoom(deps(), "unlock-nothing")).resolves.toEqual({ changed: false, unlockedBy: null });
      expect((await db.doc("rooms/unlock-nothing").get()).exists).toBe(false);
    });
  });

  describe("forceUnlock（02 の F-32）", () => {
    it("作成者が open のルームを強制解禁すると、準備OKが 0 人でも unlocked になる", async () => {
      const { roomId } = await addRoom("unlock-force");
      await expect(forceUnlock(deps(), "alice", { roomId })).resolves.toEqual({});
      expect(await roomData(roomId)).toMatchObject({ status: "unlocked", forcedUnlock: true, readyCount: 0 });
    });

    it("作成者以外は強制解禁できない", async () => {
      const { roomId } = await addRoom("unlock-notowner");
      await expectReason(forceUnlock(deps(), "bob", { roomId }), "permission-denied", "not-room-owner");
      await expectReason(forceUnlock(deps(), "zoe", { roomId }), "permission-denied", "not-room-owner");
      expect(await roomData(roomId)).toMatchObject({ status: "open", forcedUnlock: false });
    });

    it("もう unlocked なら何も書かずに成功する（forcedUnlock は立てない）", async () => {
      const { roomId } = await addRoom("unlock-already", { ready: ["alice", "bob", "carol"] });
      await waitForRoom(roomId, { status: "unlocked" });
      await expect(forceUnlock(deps(), "alice", { roomId })).resolves.toEqual({});
      expect(await roomData(roomId)).toMatchObject({ status: "unlocked", forcedUnlock: false });
    });

    it.each(["drawn", "closed"])("%s では強制解禁できない", async (status) => {
      const { roomId } = await addRoom(`unlock-${status}`, { status });
      await expectReason(forceUnlock(deps(), "alice", { roomId }), "failed-precondition", "room-already-decided");
      expect(await roomData(roomId)).toMatchObject({ status, forcedUnlock: false });
    });

    it("ルームが無い・入力が正しくない", async () => {
      await expectReason(forceUnlock(deps(), "alice", { roomId: "unlock-none" }), "not-found", "room-not-found");
      await expectReason(forceUnlock(deps(), "alice", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
    });
  });

  describe("checkDeadlines（締切日時の判定を直接呼ぶ）", () => {
    it("締切日時を過ぎた open のルームだけを unlocked にする（準備OKが 0 人でも）", async () => {
      const past = Timestamp.fromMillis(Date.now() - 1000);
      const future = Timestamp.fromMillis(Date.now() + HOUR_MS);
      // 作成者だけのルームにして、トリガーが動くのを作成の 1 回だけにする（締切を過ぎた後にトリガーが重ならない）
      const { roomId: due } = await addRoom("unlock-due", { members: ["alice"], unlockRule: "deadline", deadlineAt: future });
      const { roomId: later } = await addRoom("unlock-later", { members: ["bob"], unlockRule: "deadline", deadlineAt: future });
      const { roomId: counted } = await addRoom("unlock-count", { members: ["carol"] });
      // ルームの更新ではトリガーが動かない。締切を過ぎた状態にする
      await db.doc(`rooms/${due}`).update({ "settings.deadlineAt": past });

      await expect(unlockPassedDeadlines(deps())).resolves.toEqual({ rooms: 1, unlocked: 1 });
      expect((await roomData(due)).status).toBe("unlocked");
      expect((await roomData(later)).status).toBe("open");
      expect((await roomData(counted)).status).toBe("open");

      // もう一度呼んでも、unlocked のルームは対象に入らない
      await expect(unlockPassedDeadlines(deps())).resolves.toEqual({ rooms: 0, unlocked: 0 });
    });

    it("締切日時で解禁した後に準備OKを取り消しても unlocked のまま", async () => {
      const past = Timestamp.fromMillis(Date.now() - 1000);
      const { roomId } = await addRoom("unlock-deadline-cancel", { unlockRule: "deadline", deadlineAt: past, ready: ["bob"] });
      // メンバーを作った時点で締切を過ぎているので、トリガーかスケジュールのどちらかが解禁する
      await unlockPassedDeadlines(deps());
      await waitForRoom(roomId, { status: "unlocked" });
      await setReady(roomId, "bob", false);
      await waitForRoom(roomId, { readyCount: 0, status: "unlocked" });
    }, TRIGGER_TIMEOUT_MS * 3);

    it("drawn・closed のルームは締切を過ぎていても対象にしない", async () => {
      const past = Timestamp.fromMillis(Date.now() - 1000);
      for (const status of ["drawn", "closed"]) {
        await addRoom(`unlock-dl-${status}`, { members: ["alice"], unlockRule: "deadline", deadlineAt: past, status });
      }
      await expect(unlockPassedDeadlines(deps())).resolves.toEqual({ rooms: 0, unlocked: 0 });
      expect((await roomData("unlock-dl-drawn")).status).toBe("drawn");
      expect((await roomData("unlock-dl-closed")).status).toBe("closed");
    });
  });
});
