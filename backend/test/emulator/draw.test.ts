/**
 * 抽選（05 の §5 の `drawGacha`・02 の F-40）を Emulator で確かめる（06 の §2「drawGacha を2つ同時に呼んでも抽選記録が1件」）。
 * - 処理を Admin SDK で直接呼ぶもの（乱数を差し替えて当選を決める）
 * - client SDK の `httpsCallable` で Functions の Emulator を呼ぶもの（認証・リージョン・同時に 2 人が回したとき）
 *
 * メンバーを書くと `onMemberWrite`（トリガー）が数え直すので、ルームを作ったら数え直しが済むまで待ってから回す。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `draw-` を付ける。
 */
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable, type Functions } from "firebase/functions";
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { FUNCTIONS_REGION } from "../../functions/src/config";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { DRAW_RANDOM_RANGE } from "../../functions/src/domain/draw";
import { computeOdds } from "../../functions/src/domain/probability";
import { cryptoRandomInt, type RandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { drawGacha } from "../../functions/src/draw/service";
import { proposeReroll, voteReroll } from "../../functions/src/reroll/service";
import { forceUnlock } from "../../functions/src/unlock/service";
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

/** 決まった値を返す乱数（0 なら候補の ID 順の先頭が当たる） */
function fixed(value: number): RandomInt {
  return () => value;
}

describe("抽選（drawGacha）", () => {
  let app: App;
  let db: Firestore;

  /** 外部のもの（乱数を差し替える。今の時刻は実際の時刻。トリガーも実際の時刻で判定する） */
  function deps(random: RandomInt = fixed(0)): ServiceDeps {
    return { db, random, nowMs: () => Date.now() };
  }

  /** ルームのドキュメントの値 */
  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  /** 抽選の記録の数 */
  async function drawCount(roomId: string): Promise<number> {
    return (await db.collection(`rooms/${roomId}/draws`).get()).size;
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
   * ルームを作る。先頭の人が作成者で、`ready` の人は準備OK（既定は全員）。候補は ID → いいねした人。
   * `memberCount`・`readyCount` を -1 で作り、トリガーが数え直した値になるまで待ってから返す。
   */
  async function addRoom(
    roomId: string,
    options: {
      members?: string[];
      ready?: string[];
      status?: string;
      forcedUnlock?: boolean;
      rerollStatus?: string;
      likeMode?: string;
      candidates?: Record<string, string[]>;
      excludedCandidateIds?: string[];
      currentDrawId?: string | null;
      winnerCandidateId?: string | null;
    } = {},
  ): Promise<string> {
    const members = options.members ?? ["alice", "bob", "carol"];
    const ready = new Set(options.ready ?? members);
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: members[0],
      inviteCode: "DRAWQQ",
      status: options.status ?? "unlocked",
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: options.likeMode ?? "boost" },
      forcedUnlock: options.forcedUnlock ?? false,
      memberIds: members,
      memberCount: -1,
      readyCount: -1,
      candidateCount: Object.keys(options.candidates ?? {}).length,
      adFreeSponsor: null,
      currentDrawId: options.currentDrawId ?? null,
      winnerCandidateId: options.winnerCandidateId ?? null,
      excludedCandidateIds: options.excludedCandidateIds ?? [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: options.rerollStatus ?? "none" },
      createdAt: Timestamp.now(),
      drawnAt: null,
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
    for (const [candidateId, likedBy] of Object.entries(options.candidates ?? {})) {
      await db.doc(`rooms/${roomId}/candidates/${candidateId}`).set({
        place: { name: candidateId, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
        category: "sea",
        note: "",
        url: null,
        postedBy: members[0],
        postedByName: members[0],
        colorIndex: 0,
        likedBy,
        fromPastIdeaId: null,
        createdAt: Timestamp.now(),
      });
    }
    await waitForRoom(roomId, { memberCount: members.length, readyCount: ready.size });
    return roomId;
  }

  /** 3 件の候補（いいね 2・1・0） */
  const CANDIDATES = { "c-a": ["bob", "carol"], "c-b": ["alice"], "c-c": [] };

  beforeAll(() => {
    ({ app, db } = openAdmin("draw"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("drawGacha（処理を直接呼ぶ）", () => {
    it(
      "解禁したルームで回すと、抽選の記録を作ってルームを drawn にする（05 の §3 のフィールド）",
      async () => {
        const roomId = await addRoom("draw-basic", { candidates: CANDIDATES });
        const result = await drawGacha(deps(fixed(0)), "bob", { roomId });
        expect(result).toMatchObject({ candidateId: "c-a", alreadyDrawn: false });

        const room = await roomData(roomId);
        expect(room).toMatchObject({ status: "drawn", currentDrawId: result.drawId, winnerCandidateId: "c-a" });
        const draw = (await db.doc(`rooms/${roomId}/draws/${result.drawId}`).get()).data();
        const odds = computeOdds(
          [
            { id: "c-a", likeCount: 2 },
            { id: "c-b", likeCount: 1 },
            { id: "c-c", likeCount: 0 },
          ],
          "boost",
        );
        expect(draw).toMatchObject({
          candidateId: "c-a",
          probability: odds.odds.get("c-a")?.probability,
          weights: { "c-a": 1 + Math.SQRT2, "c-b": 2, "c-c": 1 },
          drawnBy: "bob",
          drawnByName: "bobさん",
          isReroll: false,
        });
        // 日時はどちらもサーバーの時刻（同じ書き込みの serverTimestamp）
        expect(draw?.createdAt).toBeInstanceOf(Timestamp);
        expect((room.drawnAt as Timestamp).isEqual(draw?.createdAt as Timestamp)).toBe(true);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "乱数で区間の終わりを引くと、ID 順の最後の候補が当たる（Firestore から読んだ順によらない）",
      async () => {
        const roomId = await addRoom("draw-last", { candidates: { "c-z": [], "c-a": ["bob"], "c-m": [] } });
        const result = await drawGacha(deps(fixed(DRAW_RANDOM_RANGE - 1)), "alice", { roomId });
        expect(result.candidateId).toBe("c-z");
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "2 回目は抽選せずに同じ drawId を返し、記録は 1 件のまま（02 の §6.1「2人目には既存の結果を返す」）",
      async () => {
        const roomId = await addRoom("draw-twice", { candidates: CANDIDATES });
        const first = await drawGacha(deps(fixed(0)), "alice", { roomId });
        const second = await drawGacha(deps(fixed(DRAW_RANDOM_RANGE - 1)), "carol", { roomId });
        expect(second).toEqual({ drawId: first.drawId, candidateId: first.candidateId, alreadyDrawn: true });
        expect(await drawCount(roomId)).toBe(1);
        expect((await roomData(roomId)).winnerCandidateId).toBe(first.candidateId);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "06 の §2: 同時に 2 回呼んでも記録は 1 件で、どちらも同じ drawId と当選を受け取る",
      async () => {
        const roomId = await addRoom("draw-concurrent", { candidates: CANDIDATES });
        const results = await Promise.all([
          drawGacha(deps(cryptoRandomInt), "alice", { roomId }),
          drawGacha(deps(cryptoRandomInt), "bob", { roomId }),
          drawGacha(deps(cryptoRandomInt), "carol", { roomId }),
        ]);
        expect(new Set(results.map((result) => result.drawId)).size).toBe(1);
        expect(new Set(results.map((result) => result.candidateId)).size).toBe(1);
        expect(results.filter((result) => !result.alreadyDrawn)).toHaveLength(1);
        expect(await drawCount(roomId)).toBe(1);
        expect((await roomData(roomId)).currentDrawId).toBe(results[0].drawId);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "メンバーでない・ルームが無い・入力が正しくないときは断る",
      async () => {
        const roomId = await addRoom("draw-auth", { candidates: CANDIDATES });
        await expectReason(drawGacha(deps(), "mallory", { roomId }), "permission-denied", "not-room-member");
        await expectReason(drawGacha(deps(), "alice", { roomId: "draw-missing" }), "not-found", "room-not-found");
        await expectReason(drawGacha(deps(), "alice", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
        await expectReason(drawGacha(deps(), "alice", null), "invalid-argument", "invalid-argument");
        expect(await drawCount(roomId)).toBe(0);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "open は room-not-unlocked・closed は room-already-decided",
      async () => {
        const open = await addRoom("draw-open", { status: "open", ready: ["alice"], candidates: CANDIDATES });
        await waitForRoom(open, { status: "open" });
        await expectReason(drawGacha(deps(), "alice", { roomId: open }), "failed-precondition", "room-not-unlocked");

        const closed = await addRoom("draw-closed", { status: "closed", candidates: CANDIDATES });
        await expectReason(drawGacha(deps(), "alice", { roomId: closed }), "failed-precondition", "room-already-decided");
        expect(await drawCount(open)).toBe(0);
        expect(await drawCount(closed)).toBe(0);
      },
      TRIGGER_TIMEOUT_MS * 3,
    );

    it(
      "unlocked と書いてあっても、数え直すと条件を満たさない（参加の直後でトリガーが戻す前）なら room-not-unlocked",
      async () => {
        const roomId = await addRoom("draw-recount", { status: "open", ready: ["alice", "bob"], candidates: CANDIDATES });
        await waitForRoom(roomId, { status: "open", readyCount: 2 });
        // 全員OKで解禁した直後に carol が参加し、onMemberWrite がまだ open に戻していない状態を作る
        // （ルームへの書き込みでは onMemberWrite は動かないので、この値のまま drawGacha を呼べる）
        await db.doc(`rooms/${roomId}`).update({ status: "unlocked", readyCount: 3 });
        await expectReason(drawGacha(deps(), "alice", { roomId }), "failed-precondition", "room-not-unlocked");
        expect(await drawCount(roomId)).toBe(0);
        expect((await roomData(roomId)).status).toBe("unlocked");
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "強制解禁したルームは、準備OKが 0 人でも回せる（02 の F-32）",
      async () => {
        const roomId = await addRoom("draw-forced", { status: "open", ready: [], candidates: CANDIDATES });
        await forceUnlock(deps(), "alice", { roomId });
        const result = await drawGacha(deps(fixed(0)), "carol", { roomId });
        expect(result).toMatchObject({ candidateId: "c-a", alreadyDrawn: false });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "06 の §2: 引き直しの可決の後は、除外した候補は当選せず、記録は引き直しの抽選になる（準備OKの数は見ない）",
      async () => {
        const roomId = await addRoom("draw-reroll", {
          ready: ["alice"],
          rerollStatus: "passed",
          candidates: CANDIDATES,
          excludedCandidateIds: ["c-a"],
          currentDrawId: "d-old",
          winnerCandidateId: "c-a",
        });
        await waitForRoom(roomId, { status: "unlocked" });
        const result = await drawGacha(deps(fixed(0)), "bob", { roomId });
        expect(result.candidateId).toBe("c-b");
        expect(result.drawId).not.toBe("d-old");
        const draw = (await db.doc(`rooms/${roomId}/draws/${result.drawId}`).get()).data();
        expect(draw).toMatchObject({ isReroll: true, weights: { "c-b": 2, "c-c": 1 } });
        expect(Object.keys(draw?.weights as object)).not.toContain("c-a");
        expect(await roomData(roomId)).toMatchObject({ status: "drawn", currentDrawId: result.drawId, winnerCandidateId: "c-b" });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "02 の F-43 の AC: 引き直しが可決すると、前回の当選候補は次の抽選の対象から外れる。2 回目は提案できない",
      async () => {
        const roomId = await addRoom("draw-reroll-flow", { candidates: CANDIDATES });
        const first = await drawGacha(deps(fixed(0)), "alice", { roomId });
        expect(first.candidateId).toBe("c-a");
        // 3 人のルームで、提案者（自動で賛成）と bob の賛成で過半数
        await proposeReroll(deps(), "carol", { roomId });
        await voteReroll(deps(), "bob", { roomId, approve: true });
        expect(await roomData(roomId)).toMatchObject({ status: "unlocked", excludedCandidateIds: ["c-a"] });

        // 前回と同じ乱数でも、前回の当選（いいねが最も多い c-a）は当たらない
        const second = await drawGacha(deps(fixed(0)), "alice", { roomId });
        expect(second).toMatchObject({ candidateId: "c-b", alreadyDrawn: false });
        expect(second.drawId).not.toBe(first.drawId);
        const draw = (await db.doc(`rooms/${roomId}/draws/${second.drawId}`).get()).data();
        expect(draw).toMatchObject({ isReroll: true, weights: { "c-b": 2, "c-c": 1 } });
        expect(Object.keys(draw?.weights as object)).not.toContain("c-a");
        // どの乱数でも c-a は当たらない（区間の終わりも確かめる）
        await db.doc(`rooms/${roomId}`).update({ status: "unlocked" });
        const last = await drawGacha(deps(fixed(DRAW_RANDOM_RANGE - 1)), "bob", { roomId });
        expect(last.candidateId).toBe("c-c");
        expect(await drawCount(roomId)).toBe(3);

        await expectReason(proposeReroll(deps(), "alice", { roomId }), "failed-precondition", "reroll-used");
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "候補が 0 件・すべて除外したときは no-candidates（02 の F-40「候補がありません」）",
      async () => {
        const empty = await addRoom("draw-empty");
        await expectReason(drawGacha(deps(), "alice", { roomId: empty }), "failed-precondition", "no-candidates");
        const excluded = await addRoom("draw-all-excluded", {
          rerollStatus: "passed",
          candidates: { "c-a": [] },
          excludedCandidateIds: ["c-a"],
        });
        await expectReason(drawGacha(deps(), "alice", { roomId: excluded }), "failed-precondition", "no-candidates");
        expect((await roomData(empty)).status).toBe("unlocked");
      },
      TRIGGER_TIMEOUT_MS * 3,
    );
  });

  describe("drawGacha（Functions の Emulator の Callable）", () => {
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

    /** `drawGacha` を呼ぶ */
    async function callDraw(functions: Functions, data: unknown): Promise<{ drawId: string; candidateId: string; alreadyDrawn: boolean }> {
      const callable = httpsCallable<unknown, { drawId: string; candidateId: string; alreadyDrawn: boolean }>(
        functions,
        "drawGacha",
      );
      return (await callable(data)).data;
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
      const { functions } = await client("draw-anonymous", false);
      await expect(callDraw(functions, { roomId: "draw-x" })).rejects.toMatchObject({
        code: "functions/unauthenticated",
        details: { reason: "unauthenticated" },
      });
    });

    it(
      "2 人がほぼ同時に回しても、当選は 1 件だけで、2 人とも同じ結果を受け取る（02 の F-40 の AC）",
      async () => {
        const first = await client("draw-first");
        const second = await client("draw-second");
        const roomId = await addRoom("draw-callable", { members: [first.uid, second.uid], candidates: CANDIDATES });
        const results = await Promise.all([
          callDraw(first.functions, { roomId }),
          callDraw(second.functions, { roomId }),
        ]);
        expect(results[0].drawId).toBe(results[1].drawId);
        expect(results[0].candidateId).toBe(results[1].candidateId);
        expect(results.filter((result) => !result.alreadyDrawn)).toHaveLength(1);
        expect(await drawCount(roomId)).toBe(1);
        expect(await roomData(roomId)).toMatchObject({ status: "drawn", winnerCandidateId: results[0].candidateId });
      },
      TRIGGER_TIMEOUT_MS * 3,
    );
  });
});
