/**
 * Firestore のセキュリティルールのテスト（05 の §4・06 の §2「メンバー以外は読めない」「ready は自分の分だけ変更できる」）。
 * データは withSecurityRulesDisabled で入れ、クライアント（ルールを通る）の読み書きを確かめる。
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestContext,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";

import { BACKEND_DIR, parseHostPort, PROJECT_ID, requireEnv } from "./env";

/** ルーム room1（alice が作成者、bob がメンバー。carol はメンバーでない） */
function roomData(status = "open") {
  return {
    name: "年末の旅行",
    ownerId: "alice",
    inviteCode: "DK729Q",
    status,
    settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
    forcedUnlock: false,
    memberIds: ["alice", "bob"],
    memberCount: 2,
    readyCount: 0,
    candidateCount: 0,
    adFreeSponsor: null,
    currentDrawId: null,
    winnerCandidateId: null,
    excludedCandidateIds: [],
    reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
    createdAt: Timestamp.fromMillis(0),
    drawnAt: null,
    closedAt: null,
  };
}

/** メンバーのドキュメント */
function memberData(role: "owner" | "member") {
  return {
    displayName: role === "owner" ? "ありす" : "ぼぶ",
    avatarColor: "#B8321A",
    role,
    ready: false,
    joinedAt: Timestamp.fromMillis(0),
    lastSeenAt: Timestamp.fromMillis(0),
  };
}

describe("firestore.rules", () => {
  let testEnv: RulesTestEnvironment;

  /** uid のユーザーとしてのクライアント（null ならサインインしていない） */
  function as(uid: string | null): ReturnType<RulesTestContext["firestore"]> {
    return uid === null ? testEnv.unauthenticatedContext().firestore() : testEnv.authenticatedContext(uid).firestore();
  }

  /** ルール抜きでデータを入れる */
  async function seed(status = "open"): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users/alice"), {
        displayName: "ありす",
        avatarColor: "#B8321A",
        adFree: false,
        fcmTokens: [],
        createdAt: Timestamp.fromMillis(0),
      });
      await setDoc(doc(db, "rooms/room1"), roomData(status));
      await setDoc(doc(db, "rooms/room1/members/alice"), memberData("owner"));
      await setDoc(doc(db, "rooms/room1/members/bob"), memberData("member"));
      await setDoc(doc(db, "rooms/room1/candidates/c1"), { postedBy: "alice", likedBy: [] });
      await setDoc(doc(db, "inviteCodes/DK729Q"), { roomId: "room1", createdAt: Timestamp.fromMillis(0) });
    });
  }

  beforeAll(async () => {
    // emulators:exec が渡す接続先を使う（DG_EMULATOR_PORT_OFFSET でずらしたポート）
    const { host, port } = parseHostPort(requireEnv("FIRESTORE_EMULATOR_HOST"));
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        host,
        port,
        rules: readFileSync(join(BACKEND_DIR, "firestore.rules"), "utf8"),
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  afterAll(async () => {
    await testEnv.clearFirestore();
    await testEnv.cleanup();
  });

  describe("users", () => {
    beforeEach(() => seed());

    it("本人は自分のユーザーを読める", async () => {
      await assertSucceeds(getDoc(doc(as("alice"), "users/alice")));
    });

    it("他人のユーザー・サインインしていない人は読めない", async () => {
      await assertFails(getDoc(doc(as("bob"), "users/alice")));
      await assertFails(getDoc(doc(as(null), "users/alice")));
    });

    it("ユーザーを直接作れない（saveProfile を通す）", async () => {
      await assertFails(
        setDoc(doc(as("bob"), "users/bob"), {
          displayName: "ぼぶ",
          avatarColor: "#B8321A",
          adFree: false,
          fcmTokens: [],
          createdAt: serverTimestamp(),
        }),
      );
    });

    it("本人は通知トークンだけを直接変えられる", async () => {
      await assertSucceeds(updateDoc(doc(as("alice"), "users/alice"), { fcmTokens: ["token"] }));
      await assertFails(updateDoc(doc(as("alice"), "users/alice"), { fcmTokens: "token" }));
    });

    it("通知トークンは 10 個まで・要素は空でない 4096 文字以下の文字列だけ", async () => {
      const alice = doc(as("alice"), "users/alice");
      const tokens = Array.from({ length: 10 }, (_, index) => `token${String(index)}`);
      await assertSucceeds(updateDoc(alice, { fcmTokens: [] }));
      await assertSucceeds(updateDoc(alice, { fcmTokens: tokens }));
      await assertSucceeds(updateDoc(alice, { fcmTokens: ["t".repeat(4096)] }));
      await assertFails(updateDoc(alice, { fcmTokens: [...tokens, "token10"] }));
      for (const invalid of [1, null, "", "t".repeat(4097), { token: "x" }]) {
        await assertFails(updateDoc(alice, { fcmTokens: ["token", invalid] }));
      }
      // 10 番目（最後の番号）の要素も確かめる
      await assertFails(updateDoc(alice, { fcmTokens: [...tokens.slice(0, 9), 1] }));
    });

    it("購入済み・色・表示名は直接変えられない", async () => {
      await assertFails(updateDoc(doc(as("alice"), "users/alice"), { adFree: true }));
      await assertFails(updateDoc(doc(as("alice"), "users/alice"), { avatarColor: "#000000" }));
      await assertFails(updateDoc(doc(as("alice"), "users/alice"), { displayName: "あ" }));
    });

    it("他人の通知トークンは変えられない・ユーザーを消せない", async () => {
      await assertFails(updateDoc(doc(as("bob"), "users/alice"), { fcmTokens: ["token"] }));
      await assertFails(deleteDoc(doc(as("alice"), "users/alice")));
    });
  });

  describe("rooms", () => {
    beforeEach(() => seed());

    it("メンバーはルームを読める", async () => {
      await assertSucceeds(getDoc(doc(as("alice"), "rooms/room1")));
      await assertSucceeds(getDoc(doc(as("bob"), "rooms/room1")));
    });

    it("メンバー以外・サインインしていない人は読めない", async () => {
      await assertFails(getDoc(doc(as("carol"), "rooms/room1")));
      await assertFails(getDoc(doc(as(null), "rooms/room1")));
    });

    it("ホームの一覧（memberIds array-contains 自分）は読める・他人の一覧は読めない", async () => {
      const mine = await assertSucceeds(
        getDocs(query(collection(as("bob"), "rooms"), where("memberIds", "array-contains", "bob"))),
      );
      expect(mine.docs.map((snapshot) => snapshot.id)).toEqual(["room1"]);
      await assertFails(getDocs(query(collection(as("carol"), "rooms"), where("memberIds", "array-contains", "bob"))));
      await assertFails(getDocs(collection(as("carol"), "rooms")));
    });

    it("ルームを直接作る・変える・消すことはできない（作成者でも）", async () => {
      await assertFails(setDoc(doc(as("carol"), "rooms/room2"), { ...roomData(), ownerId: "carol", memberIds: ["carol"] }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { status: "unlocked" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1"), { memberIds: ["alice", "bob", "carol"] }));
      await assertFails(deleteDoc(doc(as("alice"), "rooms/room1")));
    });
  });

  describe("members", () => {
    it("メンバーはメンバーの一覧を読める・メンバー以外は読めない", async () => {
      await seed();
      await assertSucceeds(getDocs(collection(as("bob"), "rooms/room1/members")));
      await assertFails(getDocs(collection(as("carol"), "rooms/room1/members")));
      await assertFails(getDoc(doc(as("carol"), "rooms/room1/members/alice")));
    });

    it("自分の準備OKと lastSeenAt（サーバーの時刻）は変えられる", async () => {
      await seed();
      await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: true }));
      await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { lastSeenAt: serverTimestamp() }));
      await assertSucceeds(
        updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: false, lastSeenAt: serverTimestamp() }),
      );
    });

    it("unlocked でも準備OKを変えられる（取り消しで open に戻るため）", async () => {
      await seed("unlocked");
      await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: true }));
    });

    it("他人の準備OK・lastSeenAt は変えられない（作成者でも）", async () => {
      await seed();
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1/members/bob"), { ready: true }));
      await assertFails(updateDoc(doc(as("carol"), "rooms/room1/members/bob"), { lastSeenAt: serverTimestamp() }));
    });

    it("lastSeenAt にサーバーの時刻以外は書けない", async () => {
      await seed();
      await assertFails(
        updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { lastSeenAt: Timestamp.fromMillis(Date.now() + 86_400_000) }),
      );
    });

    it("準備OKは真偽値だけ", async () => {
      await seed();
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: "yes" }));
    });

    it("drawn・closed では準備OKを変えられない（lastSeenAt は変えられる）", async () => {
      for (const status of ["drawn", "closed"]) {
        await testEnv.clearFirestore();
        await seed(status);
        await assertFails(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: true }));
        await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { lastSeenAt: serverTimestamp() }));
      }
    });

    it("役割・表示名・参加日時は変えられない", async () => {
      await seed();
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { role: "owner" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { displayName: "なりすまし" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { joinedAt: serverTimestamp() }));
    });

    it("メンバーを直接作る・消すことはできない（参加・退出は Callable）", async () => {
      await seed();
      await assertFails(setDoc(doc(as("carol"), "rooms/room1/members/carol"), memberData("member")));
      await assertFails(deleteDoc(doc(as("bob"), "rooms/room1/members/bob")));
      await assertFails(deleteDoc(doc(as("alice"), "rooms/room1/members/bob")));
    });
  });

  describe("まだ作っていないコレクション", () => {
    beforeEach(() => seed());

    it("招待コードの索引は読み書きできない（Functions だけが使う）", async () => {
      await assertFails(getDoc(doc(as("bob"), "inviteCodes/DK729Q")));
      await assertFails(setDoc(doc(as("carol"), "inviteCodes/AAAAAA"), { roomId: "room1" }));
    });

    it("候補・抽選・過去のアイデア・報告は、メンバーでも読み書きできない", async () => {
      await assertFails(getDoc(doc(as("bob"), "rooms/room1/candidates/c1")));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/candidates/c1"), { likedBy: ["bob"] }));
      await assertFails(getDocs(collection(as("bob"), "rooms/room1/draws")));
      await assertFails(getDocs(collection(as("alice"), "users/alice/pastIdeas")));
      await assertFails(setDoc(doc(as("bob"), "reports/r1"), { roomId: "room1" }));
    });
  });
});
