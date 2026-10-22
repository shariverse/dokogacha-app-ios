/**
 * ルームの終了（F-44）と過去のアイデア（F-13）のセキュリティルールのテスト（05 の §4）。
 * - 過去のアイデア（`users/{uid}/pastIdeas`）は本人だけが読める。作るのは Functions だけで、本人でも直接は書けない
 * - ルームを `closed` にできるのは Callable の `closeRoom`・スケジュールの `autoCloseRooms` だけで、作成者でも直接は書けない
 * データは withSecurityRulesDisabled で入れ、クライアント（ルールを通る）の読み書きを確かめる。
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `close-rules-` を付ける。
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
import { collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, setDoc, Timestamp, updateDoc } from "firebase/firestore";

import { BACKEND_DIR, parseHostPort, PROJECT_ID, requireEnv } from "./env";
import { isLockTimeout, retryWhileLocked } from "./firestore-admin";

/** ルームの ID */
const ROOM_ID = "close-rules-room";

/** 過去のアイデアの値 */
const IDEA = {
  sourceRoomId: ROOM_ID,
  sourceRoomName: "年末の旅行",
  sourceClosedAt: Timestamp.fromMillis(0),
  sourceWinnerName: "城ヶ島",
  place: { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: null },
  category: "sea",
  prevLikeCount: 3,
};

/** alice が作成者で bob がメンバーのルーム（状態を選ぶ） */
function roomData(status: string) {
  return {
    name: "年末の旅行",
    ownerId: "alice",
    inviteCode: "CL0SE2",
    status,
    settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
    // メンバーを入れたときのトリガー（onMemberWrite）で状態が変わらないよう、drawn・closed だけで使う
    forcedUnlock: false,
    memberIds: ["alice", "bob"],
    memberCount: 2,
    readyCount: 0,
    candidateCount: 1,
    adFreeSponsor: null,
    currentDrawId: "d1",
    winnerCandidateId: "c1",
    excludedCandidateIds: [],
    reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
    createdAt: Timestamp.fromMillis(0),
    drawnAt: Timestamp.fromMillis(0),
    closedAt: status === "closed" ? Timestamp.fromMillis(0) : null,
  };
}

describe("ルームの終了と過去のアイデアのルール（05 の §4）", () => {
  let testEnv: RulesTestEnvironment;

  /** uid のユーザーとしてのクライアント（null ならサインインしていない） */
  function as(uid: string | null): ReturnType<RulesTestContext["firestore"]> {
    return uid === null ? testEnv.unauthenticatedContext().firestore() : testEnv.authenticatedContext(uid).firestore();
  }

  /** ルームと、alice・bob の過去のアイデアをルール抜きで入れる */
  async function seed(status: string): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, `rooms/${ROOM_ID}`), roomData(status));
      await setDoc(doc(db, "users/alice/pastIdeas/i1"), IDEA);
      await setDoc(doc(db, "users/bob/pastIdeas/i1"), IDEA);
    });
  }

  beforeAll(async () => {
    const { host, port } = parseHostPort(requireEnv("FIRESTORE_EMULATOR_HOST"));
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host, port, rules: readFileSync(join(BACKEND_DIR, "firestore.rules"), "utf8") },
    });
  });

  beforeEach(async () => {
    await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
  });

  afterAll(async () => {
    await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
    await testEnv.cleanup();
  });

  describe("過去のアイデア（users/{uid}/pastIdeas）", () => {
    beforeEach(() => seed("closed"));

    it("本人は自分の過去のアイデアを読める（終了の新しい順の一覧も）", async () => {
      await assertSucceeds(getDoc(doc(as("alice"), "users/alice/pastIdeas/i1")));
      await assertSucceeds(getDocs(collection(as("alice"), "users/alice/pastIdeas")));
      await assertSucceeds(getDocs(query(collection(as("bob"), "users/bob/pastIdeas"), orderBy("sourceClosedAt", "desc"))));
    });

    it("他人・サインインしていない人は読めない（同じルームのメンバーでも）", async () => {
      await assertFails(getDoc(doc(as("bob"), "users/alice/pastIdeas/i1")));
      await assertFails(getDocs(collection(as("bob"), "users/alice/pastIdeas")));
      await assertFails(getDoc(doc(as(null), "users/alice/pastIdeas/i1")));
    });

    it("本人でも作成・変更・削除できない（作るのはルームが終了したときの Functions だけ）", async () => {
      await assertFails(setDoc(doc(as("alice"), "users/alice/pastIdeas/i2"), IDEA));
      await assertFails(updateDoc(doc(as("alice"), "users/alice/pastIdeas/i1"), { prevLikeCount: 10 }));
      await assertFails(deleteDoc(doc(as("alice"), "users/alice/pastIdeas/i1")));
      await assertFails(setDoc(doc(as("bob"), "users/alice/pastIdeas/i3"), IDEA));
    });
  });

  describe("ルームの終了", () => {
    it("作成者でも drawn のルームを直接 closed にできない（closeRoom を通す）", async () => {
      await seed("drawn");
      await assertFails(updateDoc(doc(as("alice"), `rooms/${ROOM_ID}`), { status: "closed" }));
      await assertFails(
        updateDoc(doc(as("alice"), `rooms/${ROOM_ID}`), { status: "closed", closedAt: Timestamp.fromMillis(0) }),
      );
      await assertFails(updateDoc(doc(as("bob"), `rooms/${ROOM_ID}`), { status: "closed" }));
    });

    it("closed のルームを直接 drawn に戻せない・メンバーは closed のルームを読める（閲覧のみ）", async () => {
      await seed("closed");
      await assertFails(updateDoc(doc(as("alice"), `rooms/${ROOM_ID}`), { status: "drawn", closedAt: null }));
      await assertSucceeds(getDoc(doc(as("bob"), `rooms/${ROOM_ID}`)));
      await assertFails(getDoc(doc(as("carol"), `rooms/${ROOM_ID}`)));
    });
  });
});
