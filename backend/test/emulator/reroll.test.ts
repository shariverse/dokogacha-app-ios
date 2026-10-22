/**
 * 引き直し（05 の §5 の `proposeReroll`・`voteReroll`・`expireRerolls`・02 の F-43）を Emulator で確かめる。
 * - 処理を Admin SDK で直接呼ぶもの（提案・投票・可決・期限・同時の投票・退出での判定し直し）
 * - client SDK の `httpsCallable` で Functions の Emulator を呼ぶもの（認証・リージョン・入力の形）
 *
 * メンバーを書くと `onMemberWrite`（トリガー）が数え直すので、ルームを作ったら数え直しが済むまで待ってから操作する。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `reroll-` を付ける。
 */
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable, type Functions } from "firebase/functions";
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { FUNCTIONS_REGION } from "../../functions/src/config";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { REROLL_VOTING_DURATION_MS } from "../../functions/src/domain/constants";
import type { ServiceDeps } from "../../functions/src/deps";
import { expireRerolls, proposeReroll, voteReroll } from "../../functions/src/reroll/service";
import { leaveRoom } from "../../functions/src/rooms/service";
import { parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

/** 理由つきのエラーで失敗することを確かめる（Admin SDK で直接呼んだとき） */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

describe("引き直し（proposeReroll・voteReroll・expireRerolls）", () => {
  let app: App;
  let db: Firestore;

  /** 外部のもの（今の時刻は `nowMs` で差し替える。既定は実際の時刻） */
  function deps(nowMs: () => number = () => Date.now()): ServiceDeps {
    return { db, random: () => 0, nowMs };
  }

  /** ルームのドキュメントの値 */
  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  /** ルームの値が `expected` を満たすまで読み直す（固定の時間で待たない） */
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

  /**
   * 行き先が決まった（`drawn`）ルームを作る。先頭の人が作成者で、`ready` の人は準備OK（既定は全員）。当選は `c-win`。
   * `memberCount`・`readyCount` を -1 で作り、トリガーが数え直した値になるまで待ってから返す。
   */
  async function addRoom(
    roomId: string,
    options: { members?: string[]; ready?: string[]; status?: string; reroll?: Record<string, unknown> } = {},
  ): Promise<string> {
    const members = options.members ?? ["alice", "bob", "carol", "dave"];
    const ready = new Set(options.ready ?? members);
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: members[0],
      inviteCode: "RRLLQQ",
      status: options.status ?? "drawn",
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
      forcedUnlock: false,
      memberIds: members,
      memberCount: -1,
      readyCount: -1,
      candidateCount: 2,
      adFreeSponsor: null,
      currentDrawId: "d-1",
      winnerCandidateId: "c-win",
      excludedCandidateIds: [],
      reroll: options.reroll ?? { used: false, votesFor: [], votesAgainst: [], status: "none" },
      createdAt: Timestamp.now(),
      drawnAt: Timestamp.now(),
      closedAt: null,
    });
    for (const [index, uid] of members.entries()) {
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: `${uid}さん`,
        avatarColor: AVATAR_COLORS[0],
        role: index === 0 ? "owner" : "member",
        ready: ready.has(uid),
        joinedAt: Timestamp.fromMillis(Date.now() + index),
        lastSeenAt: Timestamp.now(),
      });
    }
    await waitForRoom(roomId, { memberCount: members.length, readyCount: ready.size });
    return roomId;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("reroll"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("処理を直接呼ぶ", () => {
    it(
      "提案すると、権利を使って投票中になり、提案者は自動で賛成（状態は drawn のまま）",
      async () => {
        const roomId = await addRoom("reroll-propose");
        await expect(proposeReroll(deps(), "bob", { roomId })).resolves.toEqual({});
        const room = await roomData(roomId);
        expect(room).toMatchObject({
          status: "drawn",
          excludedCandidateIds: [],
          reroll: { used: true, proposedBy: "bob", votesFor: ["bob"], votesAgainst: [], status: "voting" },
        });
        // 提案の日時はサーバーの時刻
        expect((room.reroll as { proposedAt: unknown }).proposedAt).toBeInstanceOf(Timestamp);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "賛成が過半数（4 人で 3 票）になったら可決し、直前の当選を除外リストに足して unlocked に戻す（準備OKはやり直さない）",
      async () => {
        const roomId = await addRoom("reroll-pass", { ready: ["alice", "bob"] });
        await proposeReroll(deps(), "alice", { roomId });
        await voteReroll(deps(), "bob", { roomId, approve: true });
        // 2 / 4 はちょうど半分なので、まだ投票中
        expect(await roomData(roomId)).toMatchObject({ status: "drawn", reroll: { status: "voting" } });
        await voteReroll(deps(), "dave", { roomId, approve: false });
        await voteReroll(deps(), "carol", { roomId, approve: true });

        expect(await roomData(roomId)).toMatchObject({
          status: "unlocked",
          excludedCandidateIds: ["c-win"],
          readyCount: 2,
          reroll: { used: true, votesFor: ["alice", "bob", "carol"], votesAgainst: ["dave"], status: "passed" },
        });
        const members = await db.collection(`rooms/${roomId}/members`).get();
        expect(members.docs.filter((doc) => doc.get("ready") === true).map((doc) => doc.id).sort()).toEqual(["alice", "bob"]);
        // 可決の後に誰かが準備OKを取り消しても open に戻らない（onMemberWrite）
        await db.doc(`rooms/${roomId}/members/bob`).update({ ready: false });
        await waitForRoom(roomId, { readyCount: 1 });
        expect((await roomData(roomId)).status).toBe("unlocked");
      },
      TRIGGER_TIMEOUT_MS * 3,
    );

    it(
      "1 人 1 票: 票を変えると前の票を取り除き、同じ票をもう一度送っても数は変わらない",
      async () => {
        const roomId = await addRoom("reroll-change");
        await proposeReroll(deps(), "alice", { roomId });
        await voteReroll(deps(), "bob", { roomId, approve: false });
        await voteReroll(deps(), "bob", { roomId, approve: false });
        expect((await roomData(roomId)).reroll).toMatchObject({ votesFor: ["alice"], votesAgainst: ["bob"] });
        await voteReroll(deps(), "bob", { roomId, approve: true });
        expect((await roomData(roomId)).reroll).toMatchObject({ votesFor: ["alice", "bob"], votesAgainst: [], status: "voting" });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "同時に投票しても票は重ならず、最後に確定した数え直しで可決する（6 人で 4 票目が過半数）",
      async () => {
        const roomId = await addRoom("reroll-concurrent", { members: ["alice", "bob", "carol", "dave", "erin", "frank"] });
        await proposeReroll(deps(), "alice", { roomId });
        await Promise.all(["bob", "carol", "dave"].map((uid) => voteReroll(deps(), uid, { roomId, approve: true })));
        const room = await roomData(roomId);
        expect(room.status).toBe("unlocked");
        expect(room.excludedCandidateIds).toEqual(["c-win"]);
        expect([...(room.reroll as { votesFor: string[] }).votesFor].sort()).toEqual(["alice", "bob", "carol", "dave"]);
        expect((room.reroll as { status: string }).status).toBe("passed");
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "2 人が同時に提案しても提案は 1 回で、もう 1 人は賛成として数える",
      async () => {
        const roomId = await addRoom("reroll-propose-twice");
        await Promise.all([proposeReroll(deps(), "bob", { roomId }), proposeReroll(deps(), "carol", { roomId })]);
        const reroll = (await roomData(roomId)).reroll as { proposedBy: string; votesFor: string[]; status: string };
        expect(["bob", "carol"]).toContain(reroll.proposedBy);
        expect([...reroll.votesFor].sort()).toEqual(["bob", "carol"]);
        expect(reroll.status).toBe("voting");
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "F-43 の AC: 可決の後・否決の後は 2 回目を提案できない",
      async () => {
        const passed = await addRoom("reroll-twice-passed", { members: ["alice"] });
        // 1 人のルームは提案者の賛成だけで可決する
        await proposeReroll(deps(), "alice", { roomId: passed });
        expect(await roomData(passed)).toMatchObject({ status: "unlocked", reroll: { status: "passed" } });
        await expectReason(proposeReroll(deps(), "alice", { roomId: passed }), "failed-precondition", "reroll-used");

        const rejected = await addRoom("reroll-twice-rejected", {
          reroll: { used: true, proposedBy: "alice", votesFor: ["alice"], votesAgainst: [], status: "rejected" },
        });
        await expectReason(proposeReroll(deps(), "bob", { roomId: rejected }), "failed-precondition", "reroll-used");
      },
      TRIGGER_TIMEOUT_MS * 3,
    );

    it(
      "メンバーでない・ルームが無い・行き先が決まる前・終了後・投票中でないときは断る",
      async () => {
        const roomId = await addRoom("reroll-errors");
        await expectReason(proposeReroll(deps(), "mallory", { roomId }), "permission-denied", "not-room-member");
        await expectReason(proposeReroll(deps(), "alice", { roomId: "reroll-missing" }), "not-found", "room-not-found");
        await expectReason(proposeReroll(deps(), "alice", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
        await expectReason(voteReroll(deps(), "alice", { roomId }), "invalid-argument", "invalid-argument");
        await expectReason(voteReroll(deps(), "bob", { roomId, approve: true }), "failed-precondition", "reroll-not-voting");
        await proposeReroll(deps(), "alice", { roomId });
        await expectReason(voteReroll(deps(), "mallory", { roomId, approve: true }), "permission-denied", "not-room-member");

        const open = await addRoom("reroll-open", { status: "open", ready: ["alice"] });
        await waitForRoom(open, { status: "open" });
        await expectReason(proposeReroll(deps(), "alice", { roomId: open }), "failed-precondition", "room-not-drawn");

        const closed = await addRoom("reroll-closed", { status: "closed" });
        await expectReason(proposeReroll(deps(), "alice", { roomId: closed }), "failed-precondition", "room-closed");
        expect((await roomData(closed)).reroll).toMatchObject({ used: false, status: "none" });
      },
      TRIGGER_TIMEOUT_MS * 4,
    );

    it(
      "投票中に反対していない人が退出すると、残りのメンバーで判定し直して可決する（賛成 2 / 4 人 → 2 / 3 人）",
      async () => {
        const roomId = await addRoom("reroll-leave");
        await proposeReroll(deps(), "alice", { roomId });
        await voteReroll(deps(), "bob", { roomId, approve: true });
        await leaveRoom(deps(), "dave", { roomId });
        expect(await roomData(roomId)).toMatchObject({
          status: "unlocked",
          memberIds: ["alice", "bob", "carol"],
          excludedCandidateIds: ["c-win"],
          reroll: { votesFor: ["alice", "bob"], status: "passed" },
        });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "退出した人の票は取り除き、過半数でなければ投票中のまま",
      async () => {
        const roomId = await addRoom("reroll-leave-voting");
        await proposeReroll(deps(), "alice", { roomId });
        await voteReroll(deps(), "bob", { roomId, approve: true });
        await leaveRoom(deps(), "bob", { roomId });
        expect(await roomData(roomId)).toMatchObject({
          status: "drawn",
          reroll: { votesFor: ["alice"], votesAgainst: [], status: "voting" },
        });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "expireRerolls: 提案から 24 時間を過ぎた投票だけを否決にし、権利は使ったまま（06 の §4 の仮決め）",
      async () => {
        const now = Date.now();
        const expired = await addRoom("reroll-expired", {
          reroll: {
            used: true,
            proposedBy: "alice",
            proposedAt: Timestamp.fromMillis(now - REROLL_VOTING_DURATION_MS),
            votesFor: ["alice", "bob"],
            votesAgainst: ["carol"],
            status: "voting",
          },
        });
        const fresh = await addRoom("reroll-fresh", {
          reroll: {
            used: true,
            proposedBy: "alice",
            proposedAt: Timestamp.fromMillis(now - REROLL_VOTING_DURATION_MS + 60_000),
            votesFor: ["alice"],
            votesAgainst: [],
            status: "voting",
          },
        });

        await expect(expireRerolls(deps(() => now))).resolves.toEqual({ rooms: 1, rejected: 1, passed: 0 });
        expect(await roomData(expired)).toMatchObject({
          status: "drawn",
          excludedCandidateIds: [],
          reroll: { used: true, votesFor: ["alice", "bob"], votesAgainst: ["carol"], status: "rejected" },
        });
        expect((await roomData(fresh)).reroll).toMatchObject({ status: "voting" });
        await expectReason(voteReroll(deps(), "dave", { roomId: expired, approve: true }), "failed-precondition", "reroll-not-voting");
        await expectReason(proposeReroll(deps(), "dave", { roomId: expired }), "failed-precondition", "reroll-used");
        // もう一度動かしても何もしない（冪等）
        await expect(expireRerolls(deps(() => now))).resolves.toEqual({ rooms: 0, rejected: 0, passed: 0 });
      },
      TRIGGER_TIMEOUT_MS * 3,
    );
  });

  describe("Functions の Emulator の Callable", () => {
    let functionsHost: { host: string; port: number };
    const apps: FirebaseApp[] = [];

    /** 匿名ログインしたクライアント */
    async function client(name: string, signIn = true): Promise<{ functions: Functions; uid: string }> {
      const firebaseApp = initializeApp({ projectId: PROJECT_ID, apiKey: "demo-api-key", appId: `demo-${name}` }, name);
      apps.push(firebaseApp);
      const auth = getAuth(firebaseApp);
      connectAuthEmulator(auth, `http://${requireEnv("FIREBASE_AUTH_EMULATOR_HOST")}`, { disableWarnings: true });
      const functions = getFunctions(firebaseApp, FUNCTIONS_REGION);
      connectFunctionsEmulator(functions, functionsHost.host, functionsHost.port);
      const uid = signIn ? (await signInAnonymously(auth)).user.uid : "";
      return { functions, uid };
    }

    /** Callable を呼ぶ */
    async function call(functions: Functions, name: "proposeReroll" | "voteReroll", data: unknown): Promise<unknown> {
      return (await httpsCallable(functions, name)(data)).data;
    }

    beforeAll(async () => {
      const hub = requireEnv("FIREBASE_EMULATOR_HUB");
      const running = (await (await fetch(`http://${hub}/emulators`)).json()) as RunningEmulators;
      const functions = running.functions;
      if (functions === undefined) {
        throw new Error("Functions の Emulator が起動していません");
      }
      functionsHost = parseHostPort(`${functions.host}:${String(functions.port)}`);
    });

    afterAll(async () => {
      await Promise.all(apps.map((firebaseApp) => deleteApp(firebaseApp)));
    });

    it("サインインしていなければ unauthenticated", async () => {
      const { functions } = await client("reroll-anonymous", false);
      await expect(call(functions, "proposeReroll", { roomId: "reroll-x" })).rejects.toMatchObject({
        code: "functions/unauthenticated",
        details: { reason: "unauthenticated" },
      });
    });

    it(
      "提案と投票を Callable で呼べ、2 人のルームは 2 人の賛成で可決する。賛成・反対が真偽値でなければ invalid-argument",
      async () => {
        const first = await client("reroll-first");
        const second = await client("reroll-second");
        const roomId = await addRoom("reroll-callable", { members: [first.uid, second.uid] });
        await expect(call(first.functions, "proposeReroll", { roomId })).resolves.toEqual({});
        await expect(call(second.functions, "voteReroll", { roomId, approve: "yes" })).rejects.toMatchObject({
          code: "functions/invalid-argument",
          details: { reason: "invalid-argument" },
        });
        expect((await roomData(roomId)).reroll).toMatchObject({ status: "voting" });
        await expect(call(second.functions, "voteReroll", { roomId, approve: true })).resolves.toEqual({});
        expect(await roomData(roomId)).toMatchObject({ status: "unlocked", excludedCandidateIds: ["c-win"] });
        await expect(call(second.functions, "proposeReroll", { roomId })).rejects.toMatchObject({
          code: "functions/failed-precondition",
          details: { reason: "reroll-used" },
        });
      },
      TRIGGER_TIMEOUT_MS * 3,
    );
  });
});
