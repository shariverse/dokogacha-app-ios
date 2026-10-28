/**
 * 投稿の報告（05 の §5 の `reportCandidate`・02 の §3.5 F-14）を Emulator で確かめる。
 * - 処理の中身（`reports/service.ts`）を Admin SDK の Firestore に対して直接呼ぶ: 報告・冪等・自分の投稿・非メンバー・`mail` のドキュメント
 * - Callable を client SDK（httpsCallable）で呼ぶ: 認証と、Functions のパラメータ `REPORT_MAIL_TO`（Emulator は `.env.demo-dokogacha` の目印）が宛先に入ること
 * Trigger Email 拡張は Emulator で動かさない（`scripts/emulator-config.cjs`）ので、メールが送られるところは確かめられない。
 * ルール（reports・mail をクライアントから読み書きできない）は firestore-rules.test.ts。
 */
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { addCandidate } from "../../functions/src/candidates/service";
import { FUNCTIONS_REGION } from "../../functions/src/config";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { reportDocumentId } from "../../functions/src/reports/logic";
import { reportCandidate } from "../../functions/src/reports/service";
import { createRoom, joinRoom } from "../../functions/src/rooms/service";
import { parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** テストで使う宛先（アドレスの形にしない目印） */
const MAIL_TO = "test-report-inbox";

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

describe("投稿の報告（reportCandidate。Emulator）", () => {
  let app: App;
  let db: Firestore;
  /** 報告の日時に使うサーバーの時刻（固定） */
  const nowMs = Date.UTC(2026, 9, 22, 11, 0, 0);

  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => nowMs };
  }

  /** プロフィールを直接作る */
  async function addUser(uid: string): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: `${uid}さん`,
      avatarColor: AVATAR_COLORS[0],
      adFree: false,
      fcmTokens: [],
      createdAt: Timestamp.now(),
    });
  }

  /** alice が作成者で bob がメンバーのルームに、alice の候補（ひとこと・参考 URL つき）を 1 件作る。carol はメンバーでない */
  async function roomWithCandidate(): Promise<{ roomId: string; candidateId: string }> {
    for (const uid of ["alice", "bob", "carol"]) {
      await addUser(uid);
    }
    const { roomId, inviteCode } = await createRoom(deps(), "alice", {
      name: "年末の旅行",
      postLimit: 3,
      unlockRule: "all",
      likeMode: "boost",
    });
    await joinRoom(deps(), "bob", { inviteCode });
    const result = await addCandidate(deps(), "alice", {
      roomId,
      place: { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48 },
      category: "sea",
      note: "海！",
      url: "https://example.com/enoshima",
    });
    if (!("candidateId" in result)) {
      throw new Error("候補を作れませんでした");
    }
    return { roomId, candidateId: result.candidateId };
  }

  async function reportCount(): Promise<number> {
    return (await db.collection("reports").get()).size;
  }

  async function mailCount(): Promise<number> {
    return (await db.collection("mail").get()).size;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("reports"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("メンバーが他人の候補を報告すると、reports に保存し、mail に運営向けのメールを 1 通書く", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    const result = await reportCandidate(deps(), "bob", { roomId, candidateId, reason: "inappropriate" }, { to: MAIL_TO });
    expect(result).toEqual({ alreadyReported: false, mailQueued: true });

    const id = reportDocumentId(roomId, candidateId, "bob");
    const report = (await db.doc(`reports/${id}`).get()).data();
    expect(report).toMatchObject({
      roomId,
      candidateId,
      reporterId: "bob",
      reason: "inappropriate",
      candidate: {
        placeName: "江の島",
        area: "神奈川・藤沢市",
        category: "sea",
        note: "海！",
        url: "https://example.com/enoshima",
        postedBy: "alice",
      },
    });
    expect(report?.createdAt).toBeInstanceOf(Timestamp);

    const mail = (await db.doc(`mail/${id}`).get()).data() as { to: string; message: { subject: string; text: string } };
    expect(mail.to).toBe(MAIL_TO);
    expect(mail.message.subject).toBe("【ドコガチャ】投稿の報告（不適切な内容）");
    const lines = mail.message.text.split("\n");
    expect(lines).toEqual(
      expect.arrayContaining([
        "理由: 不適切な内容",
        "ルーム: 年末の旅行",
        `ルームの ID: ${roomId}`,
        `候補の ID: ${candidateId}`,
        "場所: 江の島（神奈川・藤沢市）",
        "ひとこと: 海！",
        "参考URL: https://example.com/enoshima",
        "投稿した人のユーザー ID: alice",
        `報告の ID: ${id}`,
        "報告の日時: 2026-10-22T11:00:00.000Z",
      ]),
    );
    // 個人情報は最小限: 表示名と報告した人の uid は書かない
    expect(mail.message.text).not.toContain("さん");
    expect(mail.message.text).not.toContain("bob");
  });

  it("同じ人が同じ候補をもう一度報告しても、報告もメールも増えない（理由を変えても最初の報告のまま）", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    await reportCandidate(deps(), "bob", { roomId, candidateId, reason: "spam" }, { to: MAIL_TO });
    const again = await reportCandidate(deps(), "bob", { roomId, candidateId, reason: "other" }, { to: MAIL_TO });
    expect(again).toEqual({ alreadyReported: true, mailQueued: false });
    expect(await reportCount()).toBe(1);
    expect(await mailCount()).toBe(1);
    const id = reportDocumentId(roomId, candidateId, "bob");
    expect((await db.doc(`reports/${id}`).get()).get("reason")).toBe("spam");
  });

  it("同時に 2 回呼んでも、報告とメールは 1 つずつ（トランザクションで作る）", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    const results = await Promise.all([
      reportCandidate(deps(), "bob", { roomId, candidateId, reason: "spam" }, { to: MAIL_TO }),
      reportCandidate(deps(), "bob", { roomId, candidateId, reason: "spam" }, { to: MAIL_TO }),
    ]);
    expect(results.map((result) => result.alreadyReported).sort()).toEqual([false, true]);
    expect(await reportCount()).toBe(1);
    expect(await mailCount()).toBe(1);
  });

  it("自分の投稿は報告できない（cannot-report-own-candidate）。何も作らない", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    await expectReason(
      reportCandidate(deps(), "alice", { roomId, candidateId, reason: "spam" }, { to: MAIL_TO }),
      "failed-precondition",
      "cannot-report-own-candidate",
    );
    expect(await reportCount()).toBe(0);
    expect(await mailCount()).toBe(0);
  });

  it("メンバーでない人は報告できない（not-room-member）・無いルームは room-not-found・無い候補は candidate-not-found", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    await expectReason(
      reportCandidate(deps(), "carol", { roomId, candidateId, reason: "spam" }, { to: MAIL_TO }),
      "permission-denied",
      "not-room-member",
    );
    await expectReason(
      reportCandidate(deps(), "bob", { roomId: "no-room", candidateId, reason: "spam" }, { to: MAIL_TO }),
      "not-found",
      "room-not-found",
    );
    await expectReason(
      reportCandidate(deps(), "bob", { roomId, candidateId: "no-candidate", reason: "spam" }, { to: MAIL_TO }),
      "not-found",
      "candidate-not-found",
    );
    expect(await reportCount()).toBe(0);
    expect(await mailCount()).toBe(0);
  });

  it("理由が 3 つのどれでもなければ invalid-argument", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    await expectReason(
      reportCandidate(deps(), "bob", { roomId, candidateId, reason: "abuse" }, { to: MAIL_TO }),
      "invalid-argument",
      "invalid-argument",
    );
    expect(await reportCount()).toBe(0);
  });

  it("終了したルームの候補も報告できる（状態を問わない）", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    await db.doc(`rooms/${roomId}`).update({ status: "closed" });
    const result = await reportCandidate(deps(), "bob", { roomId, candidateId, reason: "other" }, { to: MAIL_TO });
    expect(result.alreadyReported).toBe(false);
    expect(await reportCount()).toBe(1);
  });

  it("宛先が空（パラメータの入れ忘れ）なら、報告は保存し、メールは書かない", async () => {
    const { roomId, candidateId } = await roomWithCandidate();
    const result = await reportCandidate(deps(), "bob", { roomId, candidateId, reason: "spam" }, { to: "" });
    expect(result).toEqual({ alreadyReported: false, mailQueued: false });
    expect(await reportCount()).toBe(1);
    expect(await mailCount()).toBe(0);
  });

  describe("Callable（httpsCallable）", () => {
    const apps: FirebaseApp[] = [];

    afterAll(async () => {
      await Promise.all(apps.map((client) => deleteApp(client)));
    });

    /** 匿名ログインしたクライアントで reportCandidate を呼ぶ関数と、その uid */
    async function signedInClient(name: string) {
      const hub = requireEnv("FIREBASE_EMULATOR_HUB");
      const running = (await (await fetch(`http://${hub}/emulators`)).json()) as RunningEmulators;
      const emulator = running.functions;
      if (emulator === undefined) {
        throw new Error("Functions の Emulator が起動していません");
      }
      const { host, port } = parseHostPort(`${emulator.host}:${String(emulator.port)}`);
      const client = initializeApp({ projectId: PROJECT_ID, apiKey: "demo-api-key", appId: `demo-${name}` }, name);
      apps.push(client);
      const auth = getAuth(client);
      connectAuthEmulator(auth, `http://${requireEnv("FIREBASE_AUTH_EMULATOR_HOST")}`, { disableWarnings: true });
      const functions = getFunctions(client, FUNCTIONS_REGION);
      connectFunctionsEmulator(functions, host, port);
      const uid = (await signInAnonymously(auth)).user.uid;
      return { uid, report: httpsCallable<unknown, { alreadyReported: boolean }>(functions, "reportCandidate") };
    }

    it("メンバーが呼ぶと報告し、宛先は Functions のパラメータ REPORT_MAIL_TO（Emulator の目印の値）になる", async () => {
      const { roomId, candidateId } = await roomWithCandidate();
      const reporter = await signedInClient("reporter");
      // 匿名ログインした uid をルームのメンバーにする（joinRoom の中身を直接呼ぶ）
      await addUser(reporter.uid);
      const inviteCode = (await db.doc(`rooms/${roomId}`).get()).get("inviteCode") as string;
      await joinRoom(deps(), reporter.uid, { inviteCode });

      const first = await reporter.report({ roomId, candidateId, reason: "spam" });
      expect(first.data).toEqual({ alreadyReported: false });
      const second = await reporter.report({ roomId, candidateId, reason: "spam" });
      expect(second.data).toEqual({ alreadyReported: true });

      const id = reportDocumentId(roomId, candidateId, reporter.uid);
      expect((await db.doc(`mail/${id}`).get()).get("to")).toBe("emulator-report-inbox");
      expect((await db.doc(`reports/${id}`).get()).get("reporterId")).toBe(reporter.uid);
    });
  });
});
