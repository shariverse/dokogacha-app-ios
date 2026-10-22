/**
 * 広告非表示の購入（05 の §5 の `verifyPurchase`・02 の §7.2 F-51）を Emulator で確かめる。
 * - 処理の中身（`purchase/service.ts`）を、署名の検証を差し替えて Admin SDK の Firestore に対して直接呼ぶ:
 *   `users.adFree`・参加中のルームの `adFreeSponsor`（最初に参加した購入者）・断るとき・何度呼んでも同じ・購入した後の参加
 * - Callable を client SDK（httpsCallable）で呼ぶ: Emulator では Xcode の StoreKit のテストの購入（署名なし）を受け付け、
 *   JWS として読めないものは purchase-invalid で断る（本物の App Store の署名はテストで作れない）
 * ルール（`adFree`・`adFreeSponsor` をクライアントから書けない）は firestore-rules.test.ts。
 */
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { FUNCTIONS_REGION } from "../../functions/src/config";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { REMOVE_ADS_PRODUCT_ID } from "../../functions/src/domain/constants";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { appError } from "../../functions/src/errors";
import type { VerifiedTransaction } from "../../functions/src/purchase/logic";
import { verifyPurchase } from "../../functions/src/purchase/service";
import type { TransactionVerifier } from "../../functions/src/purchase/verifier";
import { createRoom, joinRoom, leaveRoom } from "../../functions/src/rooms/service";
import { parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

/** テストで送る署名付きトランザクション（形だけの JWS。差し替えた検証は中身を見ない） */
const SIGNED = "eyJhbGciOiJFUzI1NiJ9.eyJ0ZXN0Ijp0cnVlfQ.c2lnbmF0dXJl";

/** 決めたトランザクションを返す検証（App Store の署名の代わり） */
function verifierReturning(overrides: Partial<VerifiedTransaction> = {}): TransactionVerifier {
  return {
    verify: () =>
      Promise.resolve({
        productId: REMOVE_ADS_PRODUCT_ID,
        transactionId: "2000000000000001",
        originalTransactionId: "2000000000000001",
        environment: "Sandbox",
        revocationDate: undefined,
        ...overrides,
      }),
  };
}

/** 署名を確かめられずに断る検証 */
const rejectingVerifier: TransactionVerifier = { verify: () => Promise.reject(appError("purchase-invalid")) };

/** 署名を確かめない JWS（Xcode の StoreKit のテストの購入の形） */
function xcodeJws(payload: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "ES256", typ: "JWT" })}.${encode(payload)}.${Buffer.from("xcode").toString("base64url")}`;
}

describe("広告非表示の購入（verifyPurchase。Emulator）", () => {
  let app: App;
  let db: Firestore;

  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Timestamp.now().toMillis() };
  }

  /** プロフィールを直接作る */
  async function addUser(uid: string, adFree = false): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: `${uid}さん`,
      avatarColor: AVATAR_COLORS[0],
      adFree,
      fcmTokens: [],
      createdAt: Timestamp.now(),
    });
  }

  async function sponsorOf(roomId: string): Promise<unknown> {
    return (await db.doc(`rooms/${roomId}`).get()).get("adFreeSponsor") as unknown;
  }

  async function adFreeOf(uid: string): Promise<unknown> {
    return (await db.doc(`users/${uid}`).get()).get("adFree") as unknown;
  }

  /** `owner` が作ったルームに、`joiners` を順に参加させる */
  async function room(owner: string, joiners: string[], name = "年末の旅行"): Promise<{ roomId: string; inviteCode: string }> {
    const created = await createRoom(deps(), owner, { name, postLimit: 3, unlockRule: "all", likeMode: "boost" });
    for (const uid of joiners) {
      await joinRoom(deps(), uid, { inviteCode: created.inviteCode });
    }
    return created;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("purchase"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("購入を確かめると adFree になり、参加中のルーム（終了したものも）の購入者が本人になる", async () => {
    for (const uid of ["alice", "bob"]) {
      await addUser(uid);
    }
    const first = await room("alice", ["bob"]);
    const second = await room("bob", [], "週末");
    await db.doc(`rooms/${second.roomId}`).update({ status: "closed" });
    const others = await room("alice", [], "別のルーム");

    const result = await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning());
    expect(result).toEqual({ adFree: true, environment: "Sandbox", rooms: 2, sponsorUpdates: 2 });
    expect(await adFreeOf("bob")).toBe(true);
    expect(await sponsorOf(first.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
    expect(await sponsorOf(second.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
    // 参加していないルームは変えない
    expect(await sponsorOf(others.roomId)).toBeNull();
    expect(await adFreeOf("alice")).toBe(false);
  });

  it("先に参加した購入者がいれば変えず、後から参加した購入者は購入した人に替える（最初に参加した人）", async () => {
    for (const uid of ["alice", "bob", "dave"]) {
      await addUser(uid);
    }
    await addUser("carol", true);
    await addUser("erin", true);
    // erin（購入済み）が先に参加したルームと、bob の後に carol（購入済み）が参加したルーム
    const kept = await room("erin", ["bob"]);
    const replaced = await room("alice", ["bob", "carol"], "週末");
    expect(await sponsorOf(kept.roomId)).toEqual({ uid: "erin", displayName: "erinさん" });
    expect(await sponsorOf(replaced.roomId)).toEqual({ uid: "carol", displayName: "carolさん" });

    const result = await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning());
    expect(result.sponsorUpdates).toBe(1);
    expect(await sponsorOf(kept.roomId)).toEqual({ uid: "erin", displayName: "erinさん" });
    expect(await sponsorOf(replaced.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
  });

  it("ルームを引いた後、adFree を書く前に確定した参加のルームにも購入者を入れる（PR #97 の持ち越し）", async () => {
    for (const uid of ["alice", "bob"]) {
      await addUser(uid);
    }
    const first = await room("alice", ["bob"]);
    const late = await room("alice", [], "週末");
    const result = await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning(), async () => {
      // まだ adFree でないプロフィールで参加が確定する（joinRoom は購入者を入れない）
      await joinRoom(deps(), "bob", { inviteCode: late.inviteCode });
      expect(await sponsorOf(late.roomId)).toBeNull();
    });
    expect(result).toMatchObject({ rooms: 2, sponsorUpdates: 2 });
    expect(await sponsorOf(first.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
    expect(await sponsorOf(late.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
  });

  it("何度呼んでも同じ（復元・端末の入れ替え）。2 回目はルームを書き換えない", async () => {
    await addUser("alice");
    await addUser("bob");
    const created = await room("alice", ["bob"]);
    await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning());
    const again = await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning());
    expect(again).toMatchObject({ adFree: true, rooms: 1, sponsorUpdates: 0 });
    expect(await sponsorOf(created.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
  });

  it("購入した後に作った・参加したルームにも購入者が入り、退出すると次の購入者に替わる（joinRoom・leaveRoom との整合）", async () => {
    for (const uid of ["alice", "bob"]) {
      await addUser(uid);
    }
    await verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifierReturning());
    const joined = await room("alice", ["bob"]);
    const created = await room("bob", ["alice"], "週末");
    expect(await sponsorOf(joined.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });
    expect(await sponsorOf(created.roomId)).toEqual({ uid: "bob", displayName: "bobさん" });

    await leaveRoom(deps(), "bob", { roomId: joined.roomId });
    expect(await sponsorOf(joined.roomId)).toBeNull();
  });

  it("署名を確かめられない・別のアイテム・取り消された購入は purchase-invalid で、何も書かない", async () => {
    await addUser("alice");
    await addUser("bob");
    const created = await room("alice", ["bob"]);
    for (const verifier of [
      rejectingVerifier,
      verifierReturning({ productId: "coins_100" }),
      verifierReturning({ revocationDate: Date.UTC(2026, 9, 1) }),
    ]) {
      await expectReason(
        verifyPurchase(deps(), "bob", { signedTransaction: SIGNED }, verifier),
        "failed-precondition",
        "purchase-invalid",
      );
    }
    expect(await adFreeOf("bob")).toBe(false);
    expect(await sponsorOf(created.roomId)).toBeNull();
  });

  it("表示名を登録する前（users が無い）は profile-required。形の正しくない入力は invalid-argument", async () => {
    await expectReason(
      verifyPurchase(deps(), "nobody", { signedTransaction: SIGNED }, verifierReturning()),
      "failed-precondition",
      "profile-required",
    );
    expect((await db.doc("users/nobody").get()).exists).toBe(false);
    await addUser("bob");
    await expectReason(
      verifyPurchase(deps(), "bob", { signedTransaction: "not-a-jws" }, verifierReturning()),
      "invalid-argument",
      "invalid-argument",
    );
    expect(await adFreeOf("bob")).toBe(false);
  });

  describe("Callable（httpsCallable）", () => {
    const apps: FirebaseApp[] = [];

    afterAll(async () => {
      await Promise.all(apps.map((client) => deleteApp(client)));
    });

    /** 匿名ログインしたクライアントで verifyPurchase を呼ぶ関数と、その uid */
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
      return { uid, verify: httpsCallable<unknown, { adFree: boolean }>(functions, "verifyPurchase") };
    }

    const xcodePurchase = {
      bundleId: "jp.shilokuma.Dokogacha",
      productId: REMOVE_ADS_PRODUCT_ID,
      transactionId: "0",
      originalTransactionId: "0",
      environment: "Xcode",
      type: "Non-Consumable",
      signedDate: Date.UTC(2026, 9, 22),
    };

    it("Emulator では Xcode の StoreKit のテストの購入を受け付け、adFree と参加中のルームの購入者を書く", async () => {
      const buyer = await signedInClient("buyer");
      await addUser("alice");
      await addUser(buyer.uid);
      const created = await room("alice", [buyer.uid]);

      const result = await buyer.verify({ signedTransaction: xcodeJws(xcodePurchase) });
      expect(result.data).toEqual({ adFree: true });
      expect(await adFreeOf(buyer.uid)).toBe(true);
      expect(await sponsorOf(created.roomId)).toEqual({ uid: buyer.uid, displayName: `${buyer.uid}さん` });
    });

    it("別のアプリ・別のアイテムの購入、JWS として読めない文字列は purchase-invalid", async () => {
      const buyer = await signedInClient("rejected");
      await addUser(buyer.uid);
      for (const signedTransaction of [
        xcodeJws({ ...xcodePurchase, bundleId: "com.example.other" }),
        xcodeJws({ ...xcodePurchase, productId: "coins_100" }),
        "a.b.c",
      ]) {
        await expect(buyer.verify({ signedTransaction })).rejects.toMatchObject({
          code: "functions/failed-precondition",
          details: { reason: "purchase-invalid" },
        });
      }
      expect(await adFreeOf(buyer.uid)).toBe(false);
    });
  });
});
