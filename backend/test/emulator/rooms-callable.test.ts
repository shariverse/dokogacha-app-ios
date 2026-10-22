/**
 * ルームと候補の Callable を、Emulator の Functions に client SDK（httpsCallable）で呼んで確かめる。
 * Auth の Emulator で匿名ログインし、アプリと同じ経路（リージョン asia-northeast1・認証・エラーの details）を通す。
 * 処理の細かいケースは rooms-service.test.ts（Firestore に直接）で確かめ、ここでは繋がり方を確かめる。
 */
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable, type Functions } from "firebase/functions";
import type { App } from "firebase-admin/app";
import type { Firestore } from "firebase-admin/firestore";

import { FUNCTIONS_REGION } from "../../functions/src/config";
import { parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

/**
 * Callable が失敗したときの client SDK のエラー。
 * firebase（JS）12 の `message` は、サーバーの文言の後ろに HTTP のステータス（` [404]` など）が付く。
 * アプリは文言を `details.reason` で選ぶので、テストも `message` は先頭だけを確かめる。
 */
interface CallableError {
  code: string;
  message: string;
  details?: unknown;
}

describe("ルームと候補の Callable（Emulator の Functions）", () => {
  let functionsHost: { host: string; port: number };
  const apps: FirebaseApp[] = [];
  let admin: App;
  let db: Firestore;

  /** 名前ごとのクライアント（signIn なら匿名ログインする） */
  async function client(name: string, signIn = true): Promise<{ functions: Functions; uid: string | null }> {
    const app = initializeApp({ projectId: PROJECT_ID, apiKey: "demo-api-key", appId: `demo-${name}` }, name);
    apps.push(app);
    const auth = getAuth(app);
    connectAuthEmulator(auth, `http://${requireEnv("FIREBASE_AUTH_EMULATOR_HOST")}`, { disableWarnings: true });
    const functions = getFunctions(app, FUNCTIONS_REGION);
    connectFunctionsEmulator(functions, functionsHost.host, functionsHost.port);
    const uid = signIn ? (await signInAnonymously(auth)).user.uid : null;
    return { functions, uid };
  }

  /** Callable を呼ぶ */
  async function call<Result>(functions: Functions, name: string, data: unknown): Promise<Result> {
    return (await httpsCallable<unknown, Result>(functions, name)(data)).data;
  }

  /** Callable が理由つきのエラーで失敗することを確かめる */
  async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<CallableError> {
    const error = await promise.then(
      () => {
        throw new Error("成功してしまった");
      },
      (caught: unknown) => caught as CallableError,
    );
    expect(error).toMatchObject({ code: `functions/${code}`, details: { reason } });
    return error;
  }

  beforeAll(async () => {
    const hub = requireEnv("FIREBASE_EMULATOR_HUB");
    const running = (await (await fetch(`http://${hub}/emulators`)).json()) as RunningEmulators;
    const functions = running.functions;
    if (functions === undefined) {
      throw new Error("Functions の Emulator が起動していません");
    }
    functionsHost = parseHostPort(`${functions.host}:${String(functions.port)}`);
    ({ app: admin, db } = openAdmin("rooms-callable"));
    await clearFirestore();
  });

  afterAll(async () => {
    await Promise.all(apps.map((app) => deleteApp(app)));
    await clearFirestore();
    await closeAdmin(admin);
  });

  it("サインインしていなければ unauthenticated（「通信できませんでした」）", async () => {
    const { functions } = await client("anonymous", false);
    const error = await expectReason(call(functions, "createRoom", {}), "unauthenticated", "unauthenticated");
    expect(error.message.startsWith("通信できませんでした")).toBe(true);
  });

  it("表示名の登録 → ルームの作成 → 招待コードで参加 → 削除まで通る", async () => {
    const alice = await client("alice");
    const bob = await client("bob");

    await expect(call(alice.functions, "saveProfile", { displayName: "ありす" })).resolves.toMatchObject({
      displayName: "ありす",
      created: true,
    });
    await call(bob.functions, "saveProfile", { displayName: "ぼぶ" });

    const created = await call<{ roomId: string; inviteCode: string }>(alice.functions, "createRoom", {
      name: "年末の旅行",
      postLimit: 3,
      unlockRule: "all",
      likeMode: "boost",
    });
    expect(created.inviteCode).toMatch(/^[A-HJ-NP-Z2-9]{6}$/u);

    const display = `${created.inviteCode.slice(0, 3)}-${created.inviteCode.slice(3)}`;
    await expect(call(bob.functions, "joinRoom", { inviteCode: display })).resolves.toEqual({
      roomId: created.roomId,
      alreadyMember: false,
    });
    const room = (await db.doc(`rooms/${created.roomId}`).get()).data();
    expect(room).toMatchObject({ ownerId: alice.uid, memberIds: [alice.uid, bob.uid], memberCount: 2 });

    const leave = await expectReason(
      call(alice.functions, "leaveRoom", { roomId: created.roomId }),
      "failed-precondition",
      "owner-cannot-leave",
    );
    expect(leave.message.startsWith("作成者はルームから退出できません")).toBe(true);
    await expectReason(
      call(bob.functions, "removeMember", { roomId: created.roomId, memberId: alice.uid }),
      "permission-denied",
      "not-room-owner",
    );
    await expect(call(alice.functions, "removeMember", { roomId: created.roomId, memberId: bob.uid })).resolves.toEqual({});
    expect((await db.doc(`rooms/${created.roomId}`).get()).data()).toMatchObject({ memberIds: [alice.uid], memberCount: 1 });
  });

  it("存在しない招待コードは「招待コードが見つかりません」", async () => {
    const carol = await client("carol");
    await call(carol.functions, "saveProfile", { displayName: "きゃろる" });
    const error = await expectReason(
      call(carol.functions, "joinRoom", { inviteCode: "ZZZ-ZZZ" }),
      "not-found",
      "invite-code-not-found",
    );
    expect(error.message.startsWith("招待コードが見つかりません")).toBe(true);
  });

  it("候補の追加（同じ場所は duplicateOf）・削除が通る。アプリの AddCandidateRequest の JSON の形を受け付ける", async () => {
    const erin = await client("erin");
    const frank = await client("frank");
    await call(erin.functions, "saveProfile", { displayName: "えりん" });
    await call(frank.functions, "saveProfile", { displayName: "ふらんく" });
    const { roomId, inviteCode } = await call<{ roomId: string; inviteCode: string }>(erin.functions, "createRoom", {
      name: "週末",
      postLimit: 1,
      unlockRule: "all",
      likeMode: "boost",
    });
    await call(frank.functions, "joinRoom", { inviteCode });

    // Swift の JSONEncoder は nil の値（mapItemId・url・fromPastIdeaId）を鍵ごと送らない
    const request = {
      roomId,
      place: { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48 },
      category: "sea",
      note: "",
    };
    const added = await call<{ candidateId?: string; duplicateOf?: string }>(frank.functions, "addCandidate", request);
    expect(Object.keys(added)).toEqual(["candidateId"]);
    const duplicate = await call<{ candidateId?: string; duplicateOf?: string }>(erin.functions, "addCandidate", request);
    expect(duplicate).toEqual({ duplicateOf: added.candidateId });

    const limit = await expectReason(
      call(frank.functions, "addCandidate", { ...request, place: { ...request.place, name: "鎌倉" } }),
      "resource-exhausted",
      "post-limit-reached",
    );
    expect(limit.message.startsWith("投稿できる数の上限に達しています")).toBe(true);

    await expect(
      call(erin.functions, "deleteCandidate", { roomId, candidateId: added.candidateId }),
    ).resolves.toEqual({});
    await expectReason(
      call(frank.functions, "deleteCandidate", { roomId, candidateId: added.candidateId }),
      "not-found",
      "candidate-not-found",
    );
    expect((await db.doc(`rooms/${roomId}`).get()).get("candidateCount")).toBe(0);
  });

  it("入力が正しくなければ invalid-argument", async () => {
    const dave = await client("dave");
    await expectReason(call(dave.functions, "saveProfile", { displayName: "" }), "invalid-argument", "invalid-argument");
    await expectReason(call(dave.functions, "leaveRoom", { roomId: "a/b" }), "invalid-argument", "invalid-argument");
  });

  it("参加前の確認（previewRoom）は、S-06 に出す値を返し、存在しないコードは「招待コードが見つかりません」", async () => {
    const grace = await client("grace");
    const henry = await client("henry");
    await call(grace.functions, "saveProfile", { displayName: "ぐれいす" });
    const { roomId, inviteCode } = await call<{ roomId: string; inviteCode: string }>(grace.functions, "createRoom", {
      name: "夏の花火大会",
      postLimit: 3,
      unlockRule: "all",
      likeMode: "boost",
    });
    // サインインしていれば、表示名の登録の前でも確かめられる。アプリの RoomPreview の JSON の形で返る
    await expect(call(henry.functions, "previewRoom", { inviteCode: inviteCode.toLowerCase() })).resolves.toEqual({
      roomId,
      name: "夏の花火大会",
      ownerName: "ぐれいす",
      memberCount: 1,
      candidateCount: 0,
      status: "open",
      alreadyMember: false,
    });
    await expect(call(grace.functions, "previewRoom", { inviteCode })).resolves.toMatchObject({ alreadyMember: true });
    const error = await expectReason(
      call(henry.functions, "previewRoom", { inviteCode: "ZZZ-ZZZ" }),
      "not-found",
      "invite-code-not-found",
    );
    expect(error.message.startsWith("招待コードが見つかりません")).toBe(true);
  });
});
