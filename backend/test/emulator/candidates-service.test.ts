/**
 * 候補の Functions の処理（addCandidate・deleteCandidate）を、Emulator の Firestore に対して直接呼んで確かめる
 * （06 の §2「addCandidate で上限・重複・状態のチェック」・02 の F-10・F-11）。Callable としての呼び出しは rooms-callable.test.ts。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { MAX_CANDIDATES } from "../../functions/src/domain/constants";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { addCandidate, deleteCandidate } from "../../functions/src/candidates/service";
import { createRoom, joinRoom } from "../../functions/src/rooms/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

/** 江の島（MapKit の識別子なし） */
const enoshima = { name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48 };

/** `roomId` に `place` を追加する入力 */
function input(roomId: string, place: Record<string, unknown> = enoshima, extra: Record<string, unknown> = {}) {
  return { roomId, place, category: "sea", note: "海！", ...extra };
}

/** 名前の違う場所（重複しない） */
function placeNamed(name: string): Record<string, unknown> {
  return { ...enoshima, name };
}

describe("候補の Functions の処理（Emulator の Firestore）", () => {
  let app: App;
  let db: Firestore;

  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
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

  /** alice が作成者で bob・carol がメンバーのルーム（投稿数の上限は `postLimit`） */
  async function room(postLimit = 3): Promise<string> {
    for (const uid of ["alice", "bob", "carol"]) {
      await addUser(uid);
    }
    const { roomId, inviteCode } = await createRoom(deps(), "alice", {
      name: "年末の旅行",
      postLimit,
      unlockRule: "all",
      likeMode: "boost",
    });
    await joinRoom(deps(), "bob", { inviteCode });
    await joinRoom(deps(), "carol", { inviteCode });
    return roomId;
  }

  /** 候補を追加して、その ID を返す（重複になったら失敗する） */
  async function add(uid: string, roomId: string, place: Record<string, unknown> = enoshima): Promise<string> {
    const result = await addCandidate(deps(), uid, input(roomId, place));
    if (!("candidateId" in result)) {
      throw new Error(`重複になった: ${result.duplicateOf}`);
    }
    return result.candidateId;
  }

  async function candidateCount(roomId: string): Promise<unknown> {
    return (await db.doc(`rooms/${roomId}`).get()).get("candidateCount");
  }

  async function candidateIds(roomId: string): Promise<string[]> {
    return (await db.collection(`rooms/${roomId}/candidates`).get()).docs.map((doc) => doc.id).sort();
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("candidates-service"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("addCandidate（02 の F-10）", () => {
    it("候補を作り、ルームの候補数を増やす（いいねは 0・投稿者名はルームの表示名・投稿日時はサーバーの時刻）", async () => {
      const roomId = await room();
      const result = await addCandidate(
        deps(),
        "bob",
        input(roomId, { ...enoshima, name: " 江の島 ", mapItemId: "I1" }, { url: "https://example.com", fromPastIdeaId: "idea1" }),
      );
      expect(result).toEqual({ candidateId: expect.any(String) as unknown });
      const id = (result as { candidateId: string }).candidateId;
      const data = (await db.doc(`rooms/${roomId}/candidates/${id}`).get()).data();
      expect(data).toMatchObject({
        place: { ...enoshima, mapItemId: "I1" },
        category: "sea",
        note: "海！",
        url: "https://example.com",
        postedBy: "bob",
        postedByName: "bobさん",
        colorIndex: 0,
        likedBy: [],
        fromPastIdeaId: "idea1",
      });
      expect(data?.createdAt).toBeInstanceOf(Timestamp);
      expect(await candidateCount(roomId)).toBe(1);
    });

    it("colorIndex は投稿順の通し番号（消しても残りの番号は詰めない）", async () => {
      const roomId = await room();
      const first = await add("bob", roomId, placeNamed("a"));
      await add("carol", roomId, placeNamed("b"));
      await add("alice", roomId, placeNamed("c"));
      await deleteCandidate(deps(), "bob", { roomId, candidateId: first });
      const fourth = await add("bob", roomId, placeNamed("d"));
      expect((await db.doc(`rooms/${roomId}/candidates/${fourth}`).get()).get("colorIndex")).toBe(3);
      expect(await candidateCount(roomId)).toBe(3);
    });

    it("同じ場所（場所名が同じで 100m 以内・MapKit の識別子が同じ）は作らずに duplicateOf を返す（自分の投稿でも）", async () => {
      const roomId = await room();
      const existing = await add("bob", roomId, { ...enoshima, mapItemId: "I1" });
      // 場所名が同じで約 56m 離れた場所
      await expect(addCandidate(deps(), "carol", input(roomId, { ...enoshima, latitude: 35.3005 }))).resolves.toEqual({
        duplicateOf: existing,
      });
      // 識別子が同じなら名前と場所が違っても同じ
      await expect(
        addCandidate(deps(), "carol", input(roomId, { ...placeNamed("江ノ島"), latitude: 35.4, mapItemId: "I1" })),
      ).resolves.toEqual({ duplicateOf: existing });
      await expect(addCandidate(deps(), "bob", input(roomId))).resolves.toEqual({ duplicateOf: existing });
      expect(await candidateIds(roomId)).toEqual([existing]);
      expect(await candidateCount(roomId)).toBe(1);
    });

    it("場所名が同じでも 100m を超えれば別の候補", async () => {
      const roomId = await room();
      await add("bob", roomId);
      await add("carol", roomId, { ...enoshima, latitude: 35.301 });
      expect(await candidateCount(roomId)).toBe(2);
    });

    it("自分の投稿数がルームの上限に達したら post-limit-reached（同じ場所なら重複を先に返す）", async () => {
      const roomId = await room(2);
      const first = await add("bob", roomId, placeNamed("a"));
      await add("bob", roomId, placeNamed("b"));
      await expectReason(addCandidate(deps(), "bob", input(roomId, placeNamed("c"))), "resource-exhausted", "post-limit-reached");
      await expect(addCandidate(deps(), "bob", input(roomId, placeNamed("a")))).resolves.toEqual({ duplicateOf: first });
      // ほかの人は上限まで投稿できる
      await add("carol", roomId, placeNamed("c"));
      expect(await candidateCount(roomId)).toBe(3);
    });

    it("ルームの候補が 200 件なら room-candidates-full", async () => {
      const roomId = await room(10);
      const batch = db.batch();
      for (let index = 0; index < MAX_CANDIDATES; index += 1) {
        batch.set(db.doc(`rooms/${roomId}/candidates/seed${String(index)}`), {
          place: { ...placeNamed(`場所${String(index)}`), mapItemId: null },
          category: "town",
          note: "",
          url: null,
          postedBy: `left${String(index)}`,
          postedByName: "退出した人",
          colorIndex: index,
          likedBy: [],
          fromPastIdeaId: null,
          createdAt: Timestamp.fromMillis(index),
        });
      }
      await batch.commit();
      await expectReason(addCandidate(deps(), "bob", input(roomId)), "resource-exhausted", "room-candidates-full");
    });

    it("drawn・closed では room-already-decided", async () => {
      const roomId = await room();
      for (const status of ["drawn", "closed"]) {
        await db.doc(`rooms/${roomId}`).update({ status });
        await expectReason(addCandidate(deps(), "bob", input(roomId)), "failed-precondition", "room-already-decided");
      }
      await db.doc(`rooms/${roomId}`).update({ status: "unlocked" });
      await add("bob", roomId);
    });

    it("メンバーでなければ not-room-member・ルームが無ければ room-not-found", async () => {
      const roomId = await room();
      await addUser("dave");
      await expectReason(addCandidate(deps(), "dave", input(roomId)), "permission-denied", "not-room-member");
      await expectReason(addCandidate(deps(), "bob", input("missing")), "not-found", "room-not-found");
      expect(await candidateCount(roomId)).toBe(0);
    });

    it("入力が正しくなければ invalid-argument（何も作らない）", async () => {
      const roomId = await room();
      await expectReason(addCandidate(deps(), "bob", input(roomId, enoshima, { note: "あ".repeat(41) })), "invalid-argument", "invalid-argument");
      await expectReason(addCandidate(deps(), "bob", input(roomId, { ...enoshima, latitude: 91 })), "invalid-argument", "invalid-argument");
      await expectReason(addCandidate(deps(), "bob", input(roomId, enoshima, { category: "museum" })), "invalid-argument", "invalid-argument");
      expect(await candidateIds(roomId)).toEqual([]);
    });

    it("同じ場所を同時に 2 回追加しても、候補は 1 件だけ（もう 1 回は duplicateOf）", async () => {
      const roomId = await room();
      const results = await Promise.all([
        addCandidate(deps(), "bob", input(roomId)),
        addCandidate(deps(), "carol", input(roomId)),
      ]);
      const ids = await candidateIds(roomId);
      expect(ids).toHaveLength(1);
      expect(results).toEqual(expect.arrayContaining([{ candidateId: ids[0] }, { duplicateOf: ids[0] }]));
      expect(await candidateCount(roomId)).toBe(1);
    });

    it("上限まで 1 件のときに同時に 2 件追加しても、上限を超えない", async () => {
      const roomId = await room(1);
      const results = await Promise.allSettled([
        addCandidate(deps(), "bob", input(roomId, placeNamed("a"))),
        addCandidate(deps(), "bob", input(roomId, placeNamed("b"))),
      ]);
      expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
      expect(results.find((result) => result.status === "rejected")).toMatchObject({
        reason: { details: { reason: "post-limit-reached" } },
      });
      expect(await candidateIds(roomId)).toHaveLength(1);
    });
  });

  describe("deleteCandidate（02 の F-11）", () => {
    it("投稿した人は自分の候補を削除できる（いいねも一緒に消え、候補数が減る）", async () => {
      const roomId = await room();
      const id = await add("bob", roomId);
      await db.doc(`rooms/${roomId}/candidates/${id}`).update({ likedBy: ["carol", "alice"] });
      await expect(deleteCandidate(deps(), "bob", { roomId, candidateId: id })).resolves.toEqual({});
      expect(await candidateIds(roomId)).toEqual([]);
      expect(await candidateCount(roomId)).toBe(0);
    });

    it("作成者は誰の候補でも削除できる", async () => {
      const roomId = await room();
      const id = await add("bob", roomId);
      await deleteCandidate(deps(), "alice", { roomId, candidateId: id });
      expect(await candidateIds(roomId)).toEqual([]);
    });

    it("投稿した人でも作成者でもなければ not-candidate-owner", async () => {
      const roomId = await room();
      const id = await add("bob", roomId);
      await expectReason(deleteCandidate(deps(), "carol", { roomId, candidateId: id }), "permission-denied", "not-candidate-owner");
      expect(await candidateIds(roomId)).toEqual([id]);
    });

    it("drawn・closed では投稿した人も作成者も削除できない", async () => {
      const roomId = await room();
      const id = await add("bob", roomId);
      for (const status of ["drawn", "closed"]) {
        await db.doc(`rooms/${roomId}`).update({ status });
        for (const uid of ["bob", "alice"]) {
          await expectReason(deleteCandidate(deps(), uid, { roomId, candidateId: id }), "failed-precondition", "room-already-decided");
        }
      }
      expect(await candidateCount(roomId)).toBe(1);
    });

    it("候補が無ければ candidate-not-found・メンバーでなければ not-room-member", async () => {
      const roomId = await room();
      const id = await add("bob", roomId);
      await deleteCandidate(deps(), "bob", { roomId, candidateId: id });
      await expectReason(deleteCandidate(deps(), "bob", { roomId, candidateId: id }), "not-found", "candidate-not-found");
      await expectReason(deleteCandidate(deps(), "dave", { roomId, candidateId: id }), "permission-denied", "not-room-member");
      expect(await candidateCount(roomId)).toBe(0);
    });
  });
});
