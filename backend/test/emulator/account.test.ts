/**
 * アカウントの削除（05 の §5 の `deleteAccount`・02 の §2.6 F-06）を Emulator で確かめる。
 * - 処理の中身（`account/service.ts`）を Admin SDK の Firestore と Auth（Auth の Emulator）で直接呼ぶこと
 * - 作成者のルームが終了したことを受けたトリガー（`onRoomClosed`）が、残るメンバーにだけ過去のアイデアを登録すること
 * - Callable として、匿名でサインインしたクライアントから呼べて、Auth のユーザーが消えること
 *
 * ルームは `createRoom`・`joinRoom` で作り、いいね・引き直し・抽選の記録・報告は Admin SDK で書き足す。
 * ほかのテストのファイルとデータが混ざらないよう、トリガーの結果はこのテストで作ったルームの ID で絞って読む。
 */
import { deleteApp as deleteClientApp, initializeApp as initializeClientApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth as getClientAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import type { App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { deleteAccount, type AccountDeletionDeps } from "../../functions/src/account/service";
import { FUNCTIONS_REGION } from "../../functions/src/config";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { createRoom, joinRoom } from "../../functions/src/rooms/service";
import { parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

const roomInput = { name: "年末の旅行", postLimit: 3, unlockRule: "all", likeMode: "boost" };

describe("アカウントの削除（deleteAccount）", () => {
  let app: App;
  let db: Firestore;
  let auth: Auth;
  const clientApps: FirebaseApp[] = [];

  function serviceDeps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
  }

  /** 削除の外部のもの（Auth の Emulator のユーザーを消す） */
  function deletionDeps(): AccountDeletionDeps {
    return { db, deleteAuthUser: async (uid) => auth.deleteUser(uid) };
  }

  /** プロフィールと Auth のユーザーを作る */
  async function addUser(uid: string, options: { adFree?: boolean; fcmTokens?: string[] } = {}): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: uid,
      avatarColor: AVATAR_COLORS[0],
      adFree: options.adFree ?? false,
      fcmTokens: options.fcmTokens ?? [],
      createdAt: Timestamp.now(),
    });
    await auth.createUser({ uid }).catch((error: unknown) => {
      if ((error as { code?: string }).code !== "auth/uid-already-exists") {
        throw error;
      }
    });
  }

  /** `owner` が作り、`members` が参加したルーム */
  async function roomOf(owner: string, members: string[]): Promise<string> {
    const { roomId, inviteCode } = await createRoom(serviceDeps(), owner, roomInput);
    for (const member of members) {
      await joinRoom(serviceDeps(), member, { inviteCode });
    }
    return roomId;
  }

  /** 候補を直接置く（`postedBy` の投稿・`likedBy` のいいね） */
  async function addCandidate(roomId: string, id: string, postedBy: string, likedBy: string[]): Promise<void> {
    await db.doc(`rooms/${roomId}/candidates/${id}`).set({
      place: { name: `場所${id}`, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
      category: "sea",
      note: "",
      url: null,
      postedBy,
      postedByName: postedBy,
      colorIndex: 0,
      likedBy,
      fromPastIdeaId: null,
      createdAt: Timestamp.now(),
    });
  }

  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  /** `roomId` から登録された `uid` の過去のアイデアの ID */
  async function pastIdeaIds(uid: string, roomId: string): Promise<string[]> {
    const snapshot = await db.collection(`users/${uid}/pastIdeas`).where("sourceRoomId", "==", roomId).get();
    return snapshot.docs.map((doc) => doc.id).sort();
  }

  /** `uid` の過去のアイデアが `expected` になるまで読み直す（トリガーが書き終えた時点で次へ進む） */
  async function waitForPastIdeas(uid: string, roomId: string, expected: string[]): Promise<void> {
    const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
    let last: string[] = [];
    while (Date.now() < deadline) {
      last = await pastIdeaIds(uid, roomId);
      if (JSON.stringify(last) === JSON.stringify([...expected].sort())) {
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
    }
    throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${uid} の過去のアイデアが ${JSON.stringify(expected)} にならない（最後: ${JSON.stringify(last)}）`);
  }

  /** Auth のユーザーがいるか */
  async function authUserExists(uid: string): Promise<boolean> {
    return auth.getUser(uid).then(
      () => true,
      (error: unknown) => {
        if ((error as { code?: string }).code === "auth/user-not-found") {
          return false;
        }
        throw error;
      },
    );
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("account"));
    requireEnv("FIREBASE_AUTH_EMULATOR_HOST");
    auth = getAuth(app);
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await Promise.all(clientApps.map((clientApp) => deleteClientApp(clientApp)));
    await clearFirestore();
    await closeAdmin(app);
  });

  it("メンバーのルームからは退出と同じに外れる（いいねの取り消し・購入者の付け替え・候補と抽選の記録と報告は残る）", async () => {
    await addUser("alice");
    await addUser("bob", { adFree: true, fcmTokens: ["token-bob"] });
    await addUser("carol", { adFree: true });
    const roomId = await roomOf("alice", ["bob", "carol"]);
    expect((await roomData(roomId)).adFreeSponsor).toEqual({ uid: "bob", displayName: "bob" });
    await addCandidate(roomId, "c1", "bob", ["alice", "carol"]);
    await addCandidate(roomId, "c2", "alice", ["bob"]);
    await db.doc(`rooms/${roomId}/draws/d1`).set({ candidateId: "c1", drawnBy: "bob", drawnByName: "bob", createdAt: Timestamp.now() });
    await db.doc("reports/r1").set({ roomId, candidateId: "c2", reporterId: "bob", reason: "spam", createdAt: Timestamp.now() });
    await db.doc("users/bob/pastIdeas/old_c9").set({ sourceRoomId: "old", prevLikeCount: 0 });

    await expect(deleteAccount(deletionDeps(), "bob")).resolves.toEqual({ leftRooms: 1, closedRooms: 0, deletedPastIdeas: 1 });

    const room = await roomData(roomId);
    expect(room).toMatchObject({ status: "open", ownerId: "alice", memberIds: ["alice", "carol"], memberCount: 2 });
    expect(room.adFreeSponsor).toEqual({ uid: "carol", displayName: "carol" });
    expect((await db.doc(`rooms/${roomId}/members/bob`).get()).exists).toBe(false);
    // 投稿した候補は残り（「退出したメンバー」の投稿として表示する）、いいねは取り消される
    expect((await db.doc(`rooms/${roomId}/candidates/c1`).get()).data()).toMatchObject({ postedBy: "bob", postedByName: "bob" });
    expect((await db.doc(`rooms/${roomId}/candidates/c2`).get()).data()?.likedBy).toEqual([]);
    // 抽選の記録と報告は残る（プライバシーポリシーの「6. 保存する期間と削除」）
    expect((await db.doc(`rooms/${roomId}/draws/d1`).get()).data()).toMatchObject({ drawnBy: "bob", drawnByName: "bob" });
    expect((await db.doc("reports/r1").get()).data()).toMatchObject({ reporterId: "bob" });
    // ユーザーのデータ（表示名・通知トークン・購入）と過去のアイデアと Auth のユーザーは消える
    expect((await db.doc("users/bob").get()).exists).toBe(false);
    expect((await db.collection("users/bob/pastIdeas").get()).size).toBe(0);
    await expect(authUserExists("bob")).resolves.toBe(false);
    // ほかの人は消えない
    expect((await db.doc("users/alice").get()).exists).toBe(true);
    await expect(authUserExists("alice")).resolves.toBe(true);
  });

  it("作成者のルームは、終了していなければ終了し、作成者を外す。過去のアイデアは残るメンバーにだけ登録される", async () => {
    await addUser("alice", { adFree: true });
    await addUser("bob");
    const roomId = await roomOf("alice", ["bob"]);
    await addCandidate(roomId, "c1", "bob", ["alice"]);
    await addCandidate(roomId, "c2", "alice", ["bob"]);

    await expect(deleteAccount(deletionDeps(), "alice")).resolves.toEqual({ leftRooms: 0, closedRooms: 1, deletedPastIdeas: 0 });

    const room = await roomData(roomId);
    expect(room).toMatchObject({ status: "closed", ownerId: "alice", memberIds: ["bob"], memberCount: 1, adFreeSponsor: null });
    expect(room.closedAt).toBeInstanceOf(Timestamp);
    expect((await db.doc(`rooms/${roomId}/members/alice`).get()).exists).toBe(false);
    expect((await db.doc(`rooms/${roomId}/candidates/c1`).get()).data()?.likedBy).toEqual([]);
    expect((await db.doc(`rooms/${roomId}/candidates/c2`).get()).data()).toMatchObject({ postedBy: "alice" });
    // 当選が無いので、両方の候補が bob の過去のアイデアになる。alice（削除した人）には登録しない
    await waitForPastIdeas("bob", roomId, [`${roomId}_c1`, `${roomId}_c2`]);
    expect(await pastIdeaIds("alice", roomId)).toEqual([]);
    expect((await db.doc("users/alice").get()).exists).toBe(false);
    await expect(authUserExists("alice")).resolves.toBe(false);
  });

  it("作成者のルームで引き直しの投票中なら、終了と同じ書き込みで否決にする（残りで過半数でも可決しない）", async () => {
    await addUser("alice");
    await addUser("bob");
    await addUser("carol");
    const roomId = await roomOf("alice", ["bob", "carol"]);
    await db.doc(`rooms/${roomId}`).update({
      status: "drawn",
      winnerCandidateId: "c1",
      currentDrawId: "d1",
      drawnAt: Timestamp.now(),
      reroll: { used: true, proposedBy: "bob", proposedAt: Timestamp.now(), votesFor: ["bob", "carol"], votesAgainst: ["alice"], status: "voting" },
    });

    await deleteAccount(deletionDeps(), "alice");

    const room = await roomData(roomId);
    expect(room.status).toBe("closed");
    expect(room.reroll).toMatchObject({ votesFor: ["bob", "carol"], votesAgainst: [], status: "rejected" });
    expect(room.excludedCandidateIds).toEqual([]);
  });

  it("メンバーの drawn のルームで引き直しの投票中なら、残りのメンバーで判定し直す（退出と同じ）", async () => {
    await addUser("alice");
    await addUser("bob");
    await addUser("carol");
    const roomId = await roomOf("alice", ["bob", "carol"]);
    await db.doc(`rooms/${roomId}`).update({
      status: "drawn",
      winnerCandidateId: "c1",
      currentDrawId: "d1",
      drawnAt: Timestamp.now(),
      reroll: { used: true, proposedBy: "alice", proposedAt: Timestamp.now(), votesFor: ["alice"], votesAgainst: ["carol"], status: "voting" },
    });

    await deleteAccount(deletionDeps(), "carol");

    // 残りは alice・bob の 2 人で、賛成 1 は過半数（2 人の半分より多い）に届かない
    expect((await roomData(roomId)).reroll).toMatchObject({ votesFor: ["alice"], votesAgainst: [], status: "voting" });
    await deleteAccount(deletionDeps(), "bob");
    // 残りは alice 1 人で、賛成 1 が過半数になり可決して unlocked に戻る
    const room = await roomData(roomId);
    expect(room).toMatchObject({ status: "unlocked", excludedCandidateIds: ["c1"] });
    expect(room.reroll).toMatchObject({ status: "passed" });
  });

  it("作成者でも終了したルームは終了し直さず、外れるだけ（closedAt を書き換えない）", async () => {
    await addUser("alice");
    await addUser("bob");
    const roomId = await roomOf("alice", ["bob"]);
    const closedAt = Timestamp.fromMillis(Date.now() - 60_000);
    await db.doc(`rooms/${roomId}`).update({ status: "closed", closedAt });

    await expect(deleteAccount(deletionDeps(), "alice")).resolves.toEqual({ leftRooms: 1, closedRooms: 0, deletedPastIdeas: 0 });

    const room = await roomData(roomId);
    expect(room).toMatchObject({ status: "closed", memberIds: ["bob"] });
    expect((room.closedAt as Timestamp).isEqual(closedAt)).toBe(true);
  });

  it("途中で失敗してもやり直せる（2 回目も成功し、Auth のユーザーが無くても失敗しない）", async () => {
    await addUser("alice");
    await addUser("bob");
    const roomId = await roomOf("alice", ["bob"]);
    // Auth のユーザーを消すところで失敗させる（Firestore のデータは消し終えている）
    const failing: AccountDeletionDeps = {
      db,
      deleteAuthUser: () => Promise.reject(new Error("Auth に繋がらない")),
    };
    await expect(deleteAccount(failing, "bob")).rejects.toThrow("Auth に繋がらない");
    await expect(authUserExists("bob")).resolves.toBe(true);

    await expect(deleteAccount(deletionDeps(), "bob")).resolves.toEqual({ leftRooms: 0, closedRooms: 0, deletedPastIdeas: 0 });
    await expect(authUserExists("bob")).resolves.toBe(false);
    await expect(deleteAccount(deletionDeps(), "bob")).resolves.toEqual({ leftRooms: 0, closedRooms: 0, deletedPastIdeas: 0 });
    expect((await roomData(roomId)).memberIds).toEqual(["alice"]);
  });

  it("ルームを引いた後に別の端末で確定した参加からも外す（プロフィールを消した後にもう一度引く。PR #104 の持ち越し）", async () => {
    await Promise.all(["alice", "bob", "carol"].map((uid) => addUser(uid)));
    const first = await roomOf("alice", ["bob"]);
    const { roomId: late, inviteCode } = await createRoom(serviceDeps(), "carol", roomInput);
    const deps: AccountDeletionDeps = {
      ...deletionDeps(),
      // 1 回目に引いた後、プロフィールを消す前に、別の端末の参加が確定する
      afterFirstPass: async () => {
        await joinRoom(serviceDeps(), "bob", { inviteCode });
      },
    };

    await expect(deleteAccount(deps, "bob")).resolves.toEqual({ leftRooms: 2, closedRooms: 0, deletedPastIdeas: 0 });
    expect((await roomData(first)).memberIds).toEqual(["alice"]);
    expect((await roomData(late)).memberIds).toEqual(["carol"]);
    expect((await db.doc(`rooms/${late}/members/bob`).get()).exists).toBe(false);
  });

  it("プロフィールを消した後の参加は確定しない（profile-required）", async () => {
    await Promise.all(["alice", "bob"].map((uid) => addUser(uid)));
    const { inviteCode } = await createRoom(serviceDeps(), "alice", roomInput);
    await db.doc("users/bob").delete();
    await expect(joinRoom(serviceDeps(), "bob", { inviteCode })).rejects.toMatchObject({ details: { reason: "profile-required" } });
  });

  it("どのルームにも参加していない・プロフィールも無い人でも成功する", async () => {
    await auth.createUser({ uid: "dave" });
    await expect(deleteAccount(deletionDeps(), "dave")).resolves.toEqual({ leftRooms: 0, closedRooms: 0, deletedPastIdeas: 0 });
    await expect(authUserExists("dave")).resolves.toBe(false);
  });

  it("Callable として、匿名でサインインしたクライアントから呼ぶと、ルームが終了して Auth のユーザーが消える", async () => {
    const hub = requireEnv("FIREBASE_EMULATOR_HUB");
    const running = (await (await fetch(`http://${hub}/emulators`)).json()) as RunningEmulators;
    if (running.functions === undefined) {
      throw new Error("Functions の Emulator が起動していません");
    }
    const functionsHost = parseHostPort(`${running.functions.host}:${String(running.functions.port)}`);
    const clientApp = initializeClientApp({ projectId: PROJECT_ID, apiKey: "demo-api-key", appId: "demo-account" }, "account-client");
    clientApps.push(clientApp);
    const clientAuth = getClientAuth(clientApp);
    connectAuthEmulator(clientAuth, `http://${requireEnv("FIREBASE_AUTH_EMULATOR_HOST")}`, { disableWarnings: true });
    const functions = getFunctions(clientApp, FUNCTIONS_REGION);
    connectFunctionsEmulator(functions, functionsHost.host, functionsHost.port);
    const uid = (await signInAnonymously(clientAuth)).user.uid;

    await httpsCallable(functions, "saveProfile")({ displayName: "ありす" });
    const created = (await httpsCallable<unknown, { roomId: string }>(functions, "createRoom")(roomInput)).data;
    await expect(httpsCallable(functions, "deleteAccount")({})).resolves.toMatchObject({ data: {} });

    expect((await roomData(created.roomId)).status).toBe("closed");
    expect((await roomData(created.roomId)).memberIds).toEqual([]);
    expect((await db.doc(`users/${uid}`).get()).exists).toBe(false);
    await expect(authUserExists(uid)).resolves.toBe(false);
  });
});
