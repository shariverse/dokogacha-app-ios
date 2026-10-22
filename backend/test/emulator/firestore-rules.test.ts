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
  arrayRemove,
  arrayUnion,
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
import { isLockTimeout, retryWhileLocked } from "./firestore-admin";

/** ルーム room1（alice が作成者、bob・dave がメンバー。carol はメンバーでない） */
function roomData(status = "open", forcedUnlock = false) {
  return {
    name: "年末の旅行",
    ownerId: "alice",
    inviteCode: "DK729Q",
    status,
    settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
    forcedUnlock,
    memberIds: ["alice", "bob", "dave"],
    memberCount: 3,
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

/** 候補のドキュメント（`postedBy` の投稿。いいねは `likedBy`） */
function candidateData(postedBy: string, likedBy: string[] = []) {
  return {
    place: { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: null },
    category: "sea",
    note: "",
    url: null,
    postedBy,
    postedByName: postedBy,
    colorIndex: 0,
    likedBy,
    fromPastIdeaId: null,
    createdAt: Timestamp.fromMillis(0),
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

  /**
   * ルール抜きでデータを入れる。
   * メンバーを入れるとトリガー（onMemberWrite）が数え直して open⇄unlocked を判定し直すので、unlocked のままにしたいときは
   * `forcedUnlock` を立てる（準備OKが 0 人の全員OK条件の unlocked は、トリガーが open に戻す）
   */
  async function seed(status = "open", forcedUnlock = false): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, "users/alice"), {
        displayName: "ありす",
        avatarColor: "#B8321A",
        adFree: false,
        fcmTokens: [],
        createdAt: Timestamp.fromMillis(0),
      });
      await setDoc(doc(db, "rooms/room1"), roomData(status, forcedUnlock));
      await setDoc(doc(db, "rooms/room1/members/alice"), memberData("owner"));
      await setDoc(doc(db, "rooms/room1/members/bob"), memberData("member"));
      await setDoc(doc(db, "rooms/room1/members/dave"), memberData("member"));
      // c1 は alice の投稿（bob がいいね済み）、c2 は bob の投稿
      await setDoc(doc(db, "rooms/room1/candidates/c1"), candidateData("alice", ["bob"]));
      await setDoc(doc(db, "rooms/room1/candidates/c2"), candidateData("bob"));
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
    await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
  });

  afterAll(async () => {
    await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
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

  describe("通知の記録（notificationLog・emulatorPushOutbox。F-60）", () => {
    beforeEach(async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await setDoc(doc(db, "rooms/room1/notificationLog/unlocked"), { kind: "unlocked", sentAt: Timestamp.fromMillis(0) });
        await setDoc(doc(db, "emulatorPushOutbox/m1"), { token: "t", body: "本文", threadId: "room1" });
      });
    });

    it("送った印は、メンバー・作成者でも読めない・作れない・消せない（もう一度送らせない）", async () => {
      await assertFails(getDoc(doc(as("alice"), "rooms/room1/notificationLog/unlocked")));
      await assertFails(setDoc(doc(as("alice"), "rooms/room1/notificationLog/drawn-d1"), { kind: "drawn" }));
      await assertFails(deleteDoc(doc(as("alice"), "rooms/room1/notificationLog/unlocked")));
    });

    it("Emulator の送った通知（トークンを含む）は読めない", async () => {
      await assertFails(getDoc(doc(as("alice"), "emulatorPushOutbox/m1")));
      await assertFails(getDocs(collection(as("bob"), "emulatorPushOutbox")));
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
      await seed("unlocked", true);
      await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: true }));
      await assertSucceeds(updateDoc(doc(as("bob"), "rooms/room1/members/bob"), { ready: false }));
    });

    it("他人の準備OKを取り消すこともできない（解禁を戻せない）・メンバーでない人は自分の分も書けない", async () => {
      await seed("unlocked", true);
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), "rooms/room1/members/bob"), { ready: true });
      });
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1/members/bob"), { ready: false }));
      await assertFails(updateDoc(doc(as("dave"), "rooms/room1/members/bob"), { ready: false }));
      // carol はメンバーでない（メンバーのドキュメントが無い）
      await assertFails(updateDoc(doc(as("carol"), "rooms/room1/members/carol"), { ready: true }));
      await assertFails(setDoc(doc(as("carol"), "rooms/room1/members/carol"), { ...memberData("member"), ready: true }));
    });

    it("サインインしていなければ準備OKを書けない", async () => {
      await seed();
      await assertFails(updateDoc(doc(as(null), "rooms/room1/members/bob"), { ready: true }));
    });

    it("ルームの readyCount・status・forcedUnlock は直接書けない（作成者でも。数え直しと解禁は Functions）", async () => {
      await seed();
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { readyCount: 3 }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { forcedUnlock: true, status: "unlocked" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1"), { "settings.unlockRule": "majority" }));
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
        await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
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

  describe("candidates", () => {
    /** uid のユーザーから見た候補 */
    function candidate(uid: string | null, candidateId: string) {
      return doc(as(uid), `rooms/room1/candidates/${candidateId}`);
    }

    /** 候補のいいねの一覧（ルール抜きで読む） */
    async function likedBy(candidateId: string): Promise<unknown> {
      let value: unknown;
      await testEnv.withSecurityRulesDisabled(async (context) => {
        value = (await getDoc(doc(context.firestore(), `rooms/room1/candidates/${candidateId}`))).get("likedBy");
      });
      return value;
    }

    it("メンバーは候補を読める・メンバー以外・サインインしていない人は読めない", async () => {
      await seed();
      await assertSucceeds(getDoc(candidate("dave", "c1")));
      await assertSucceeds(getDocs(collection(as("bob"), "rooms/room1/candidates")));
      await assertFails(getDoc(candidate("carol", "c1")));
      await assertFails(getDocs(collection(as("carol"), "rooms/room1/candidates")));
      await assertFails(getDoc(candidate(null, "c1")));
    });

    it("候補を直接作る・消すことはできない（追加・削除は Callable。作成者・投稿した人でも）", async () => {
      await seed();
      await assertFails(setDoc(candidate("bob", "c3"), candidateData("bob")));
      await assertFails(deleteDoc(candidate("bob", "c2")));
      await assertFails(deleteDoc(candidate("alice", "c2")));
    });

    it("他人の候補にいいねを付けて、取り消せる（open・unlocked）", async () => {
      for (const status of ["open", "unlocked"]) {
        await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
        // unlocked は強制解禁で作る（準備OKが 0 人の全員OK条件の unlocked は、トリガーが open に戻す）
        await seed(status, status === "unlocked");
        await assertSucceeds(updateDoc(candidate("dave", "c1"), { likedBy: arrayUnion("dave") }));
        expect(await likedBy("c1")).toEqual(["bob", "dave"]);
        await assertSucceeds(updateDoc(candidate("bob", "c1"), { likedBy: arrayRemove("bob") }));
        expect(await likedBy("c1")).toEqual(["dave"]);
        // 一覧をそのまま書いても、自分の分だけの違いなら通る
        await assertSucceeds(updateDoc(candidate("alice", "c2"), { likedBy: ["alice"] }));
      }
    });

    it("付いているのに付ける・無いのに外す書き込みは、何も変えないので通る（二度押し）", async () => {
      await seed();
      await assertSucceeds(updateDoc(candidate("bob", "c1"), { likedBy: arrayUnion("bob") }));
      await assertSucceeds(updateDoc(candidate("dave", "c1"), { likedBy: arrayRemove("dave") }));
      expect(await likedBy("c1")).toEqual(["bob"]);
    });

    it("自分の投稿にはいいねできない（F-20）", async () => {
      await seed();
      await assertFails(updateDoc(candidate("alice", "c1"), { likedBy: arrayUnion("alice") }));
      await assertFails(updateDoc(candidate("bob", "c2"), { likedBy: ["bob"] }));
    });

    it("他人の likedBy を消せない・他人の uid を足せない", async () => {
      await seed();
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: arrayRemove("bob") }));
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: [] }));
      // 自分を足して他人を消す（差が 2 人）
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: ["dave"] }));
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: arrayUnion("carol") }));
      await assertFails(updateDoc(candidate("alice", "c1"), { likedBy: arrayRemove("bob") }));
      expect(await likedBy("c1")).toEqual(["bob"]);
    });

    it("同じ uid を重ねられない・一覧以外にできない", async () => {
      await seed();
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: ["bob", "dave", "dave"] }));
      await assertFails(updateDoc(candidate("bob", "c1"), { likedBy: ["bob", "bob"] }));
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: "dave" }));
    });

    it("likedBy 以外のフィールドは変えられない（いいねと一緒でも）", async () => {
      await seed();
      await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: arrayUnion("dave"), note: "書き換え" }));
      await assertFails(updateDoc(candidate("dave", "c1"), { colorIndex: 9 }));
      await assertFails(updateDoc(candidate("alice", "c1"), { postedBy: "dave" }));
    });

    it("drawn・closed ではいいねを付けることも取り消すこともできない", async () => {
      for (const status of ["drawn", "closed"]) {
        await retryWhileLocked(() => testEnv.clearFirestore(), isLockTimeout);
        await seed(status);
        await assertFails(updateDoc(candidate("dave", "c1"), { likedBy: arrayUnion("dave") }));
        await assertFails(updateDoc(candidate("bob", "c1"), { likedBy: arrayRemove("bob") }));
      }
    });

    it("メンバー以外・サインインしていない人はいいねできない", async () => {
      await seed();
      await assertFails(updateDoc(candidate("carol", "c1"), { likedBy: arrayUnion("carol") }));
      await assertFails(updateDoc(candidate(null, "c1"), { likedBy: arrayUnion("carol") }));
    });
  });

  describe("抽選の記録（draws。05 の §4）", () => {
    /** 抽選の記録 */
    const drawData = {
      candidateId: "c2",
      probability: 0.5,
      weights: { c1: 2, c2: 1 },
      drawnBy: "bob",
      drawnByName: "ぼぶ",
      isReroll: false,
      createdAt: Timestamp.fromMillis(0),
    };

    beforeEach(async () => {
      await seed("drawn");
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "rooms/room1/draws/d1"), drawData);
      });
    });

    it("メンバーは読める（ほかの人が回した結果を受け取る。F-41）", async () => {
      await assertSucceeds(getDoc(doc(as("bob"), "rooms/room1/draws/d1")));
      await assertSucceeds(getDocs(collection(as("alice"), "rooms/room1/draws")));
    });

    it("メンバー以外・サインインしていない人は読めない", async () => {
      await assertFails(getDoc(doc(as("carol"), "rooms/room1/draws/d1")));
      await assertFails(getDocs(collection(as(null), "rooms/room1/draws")));
    });

    it("メンバーでも作成・変更・削除できない（抽選は drawGacha だけ。作成者でも）", async () => {
      await assertFails(setDoc(doc(as("bob"), "rooms/room1/draws/d2"), { ...drawData, drawnBy: "bob" }));
      await assertFails(setDoc(doc(as("alice"), "rooms/room1/draws/d2"), { ...drawData, drawnBy: "alice" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1/draws/d1"), { candidateId: "c1" }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1/draws/d1"), { probability: 1 }));
      await assertFails(deleteDoc(doc(as("alice"), "rooms/room1/draws/d1")));
      await assertFails(setDoc(doc(as("carol"), "rooms/room1/draws/d3"), drawData));
    });

    it("ルームの当選・状態は直接書き換えられない（作成者でも）", async () => {
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { winnerCandidateId: "c1" }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1"), { status: "unlocked", currentDrawId: null }));
    });

    it("引き直しの状態・票・除外リストは直接書き換えられない（作成者でも。提案・投票は Callable。F-43）", async () => {
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1"), { "reroll.votesFor": ["alice", "bob", "dave"] }));
      await assertFails(updateDoc(doc(as("bob"), "rooms/room1"), { "reroll.votesAgainst": [] }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { "reroll.status": "passed", status: "unlocked" }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { "reroll.used": false, "reroll.status": "none" }));
      await assertFails(updateDoc(doc(as("alice"), "rooms/room1"), { excludedCandidateIds: ["c1"] }));
      await assertFails(
        updateDoc(doc(as("dave"), "rooms/room1"), {
          reroll: { used: true, proposedBy: "dave", votesFor: ["dave"], votesAgainst: [], status: "voting" },
        }),
      );
    });
  });

  describe("まだ作っていないコレクション", () => {
    beforeEach(() => seed());

    it("招待コードの索引は読み書きできない（Functions だけが使う）", async () => {
      await assertFails(getDoc(doc(as("bob"), "inviteCodes/DK729Q")));
      await assertFails(setDoc(doc(as("carol"), "inviteCodes/AAAAAA"), { roomId: "room1" }));
    });

    it("報告は、メンバーでも読み書きできない（過去のアイデアは past-ideas-rules.test.ts）", async () => {
      await assertFails(setDoc(doc(as("bob"), "reports/r1"), { roomId: "room1" }));
    });
  });
});
