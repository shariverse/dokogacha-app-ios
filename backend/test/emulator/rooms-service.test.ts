/**
 * ルームの Functions の処理（createRoom・joinRoom・leaveRoom・removeMember・saveProfile）を、
 * Emulator の Firestore に対して直接呼んで確かめる（06 の §2「joinRoom で21人目が拒否される」など）。
 * 乱数を差し替えられるので、招待コードの重複を再現できる。Callable としての呼び出しは rooms-callable.test.ts。
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { MAX_MEMBERS } from "../../functions/src/domain/constants";
import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { cryptoRandomInt, type RandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { createRoom, joinRoom, leaveRoom, removeMember } from "../../functions/src/rooms/service";
import { saveProfile } from "../../functions/src/users/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** 呼ぶたびに、並びの値を順に返す乱数（招待コード 1 つで 6 回呼ばれる） */
function sequence(values: number[]): RandomInt {
  let index = 0;
  return () => values[index++ % values.length] ?? 0;
}

/** 招待コードの理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

const roomInput = { name: "年末の旅行", postLimit: 3, unlockRule: "all", likeMode: "boost" };

describe("ルームの Functions の処理（Emulator の Firestore）", () => {
  let app: App;
  let db: Firestore;

  /** 乱数を指定した外部のもの */
  function deps(random: RandomInt = cryptoRandomInt): ServiceDeps {
    return { db, random, nowMs: () => Date.now() };
  }

  /** プロフィールを直接作る（saveProfile を通さずに速く用意する） */
  async function addUser(uid: string, options: { adFree?: boolean } = {}): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: uid,
      avatarColor: AVATAR_COLORS[0],
      adFree: options.adFree ?? false,
      fcmTokens: [],
      createdAt: Timestamp.now(),
    });
  }

  /** alice が作ったルームと招待コード */
  async function aliceRoom(random?: RandomInt): Promise<{ roomId: string; inviteCode: string }> {
    await addUser("alice");
    return createRoom(deps(random), "alice", roomInput);
  }

  async function roomData(roomId: string): Promise<FirebaseFirestore.DocumentData> {
    const data = (await db.doc(`rooms/${roomId}`).get()).data();
    if (data === undefined) {
      throw new Error(`rooms/${roomId} がありません`);
    }
    return data;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("rooms-service"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("saveProfile（02 の F-01）", () => {
    it("初回はユーザーを作り、色をパレットから選んで adFree を false にする", async () => {
      const result = await saveProfile(deps(() => 2), "alice", { displayName: " ありす " });
      expect(result).toEqual({ displayName: "ありす", avatarColor: AVATAR_COLORS[2], created: true });
      const user = (await db.doc("users/alice").get()).data();
      expect(user).toMatchObject({ displayName: "ありす", avatarColor: AVATAR_COLORS[2], adFree: false, fcmTokens: [] });
      expect(user?.createdAt).toBeInstanceOf(Timestamp);
    });

    it("2 回目は表示名だけを変える（色は変えない）", async () => {
      await saveProfile(deps(() => 2), "alice", { displayName: "ありす" });
      const result = await saveProfile(deps(() => 5), "alice", { displayName: "アリス" });
      expect(result).toEqual({ displayName: "アリス", avatarColor: AVATAR_COLORS[2], created: false });
      expect((await db.doc("users/alice").get()).data()).toMatchObject({ displayName: "アリス", avatarColor: AVATAR_COLORS[2] });
    });

    it("表示名が 1〜10 文字でなければ作らない", async () => {
      await expectReason(saveProfile(deps(), "alice", { displayName: "" }), "invalid-argument", "invalid-argument");
      await expectReason(saveProfile(deps(), "alice", { displayName: "あ".repeat(11) }), "invalid-argument", "invalid-argument");
      expect((await db.doc("users/alice").get()).exists).toBe(false);
    });
  });

  describe("createRoom（02 の F-02）", () => {
    it("ルーム・作成者のメンバー・招待コードの索引を作る（作成直後は open・メンバーは作成者 1 人）", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      expect(inviteCode).toMatch(/^[A-HJ-NP-Z2-9]{6}$/u);

      const room = await roomData(roomId);
      expect(room).toMatchObject({
        name: "年末の旅行",
        ownerId: "alice",
        inviteCode,
        status: "open",
        settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
        forcedUnlock: false,
        memberIds: ["alice"],
        memberCount: 1,
        readyCount: 0,
        candidateCount: 0,
        adFreeSponsor: null,
        excludedCandidateIds: [],
        reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
      });
      expect(room.createdAt).toBeInstanceOf(Timestamp);

      const member = (await db.doc(`rooms/${roomId}/members/alice`).get()).data();
      expect(member).toMatchObject({ displayName: "alice", role: "owner", ready: false });
      expect((member?.lastSeenAt as Timestamp).isEqual(member?.joinedAt as Timestamp)).toBe(true);

      expect((await db.doc(`inviteCodes/${inviteCode}`).get()).data()).toMatchObject({ roomId });
    });

    it("締切日時は Timestamp で保存する", async () => {
      await addUser("alice");
      const deadlineAt = Date.now() + 2 * 3_600_000;
      const { roomId } = await createRoom(deps(), "alice", { ...roomInput, unlockRule: "deadline", deadlineAt });
      const room = await roomData(roomId);
      expect((room.settings as { deadlineAt: Timestamp }).deadlineAt.toMillis()).toBe(deadlineAt);
    });

    it("招待コードが重複したら作り直す（乱数を差し替えて重複を再現）", async () => {
      const first = await aliceRoom(() => 0);
      expect(first.inviteCode).toBe("AAAAAA");

      // 1 回目は使用済みの AAAAAA、2 回目は BBBBBB を作る
      const second = await createRoom(deps(sequence([0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1])), "alice", roomInput);
      expect(second.inviteCode).toBe("BBBBBB");
      expect(second.roomId).not.toBe(first.roomId);
      expect((await db.doc("inviteCodes/AAAAAA").get()).data()).toMatchObject({ roomId: first.roomId });
      expect((await db.doc("inviteCodes/BBBBBB").get()).data()).toMatchObject({ roomId: second.roomId });
      expect((await roomData(second.roomId)).inviteCode).toBe("BBBBBB");
    });

    it("重複が続いて招待コードを決められなければ invite-code-unavailable（ルームは作らない）", async () => {
      await aliceRoom(() => 0);
      await expectReason(createRoom(deps(() => 0), "alice", roomInput), "unavailable", "invite-code-unavailable");
      expect((await db.collection("rooms").get()).size).toBe(1);
    });

    it("表示名を登録していなければ作れない", async () => {
      await expectReason(createRoom(deps(), "alice", roomInput), "failed-precondition", "profile-required");
      expect((await db.collection("rooms").get()).size).toBe(0);
    });

    it("入力が正しくなければ作れない", async () => {
      await addUser("alice");
      await expectReason(createRoom(deps(), "alice", { ...roomInput, name: "" }), "invalid-argument", "invalid-argument");
      await expectReason(createRoom(deps(), "alice", { ...roomInput, postLimit: 11 }), "invalid-argument", "invalid-argument");
    });

    it("作成者が広告非表示を購入済みなら、ルームの購入者になる", async () => {
      await addUser("alice", { adFree: true });
      const { roomId } = await createRoom(deps(), "alice", roomInput);
      expect((await roomData(roomId)).adFreeSponsor).toEqual({ uid: "alice", displayName: "alice" });
    });
  });

  describe("joinRoom（02 の F-04）", () => {
    it("招待コードで参加する（準備OKは false・lastSeenAt は joinedAt と同じ）", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      await addUser("bob");
      // 表示の形・小文字でも参加できる（サーバーでも正規化する）
      const display = `${inviteCode.slice(0, 3)}-${inviteCode.slice(3)}`.toLowerCase();
      await expect(joinRoom(deps(), "bob", { inviteCode: display })).resolves.toEqual({ roomId, alreadyMember: false });

      const member = (await db.doc(`rooms/${roomId}/members/bob`).get()).data();
      expect(member).toMatchObject({ displayName: "bob", role: "member", ready: false });
      expect((member?.lastSeenAt as Timestamp).isEqual(member?.joinedAt as Timestamp)).toBe(true);
      expect(await roomData(roomId)).toMatchObject({ memberIds: ["alice", "bob"], memberCount: 2 });
    });

    it("すでにメンバーなら何も変えずに alreadyMember を返す", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      await expect(joinRoom(deps(), "alice", { inviteCode })).resolves.toEqual({ roomId, alreadyMember: true });
      expect(await roomData(roomId)).toMatchObject({ memberIds: ["alice"], memberCount: 1 });
    });

    it("存在しないコードは「招待コードが見つかりません」", async () => {
      await aliceRoom(() => 0);
      await addUser("bob");
      await expectReason(joinRoom(deps(), "bob", { inviteCode: "BBBBBB" }), "not-found", "invite-code-not-found");
      await expectReason(joinRoom(deps(), "bob", { inviteCode: "DK7-290" }), "not-found", "invite-code-not-found");
    });

    it("20 人のルームに 21 人目は参加できない", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      for (let index = 2; index <= MAX_MEMBERS; index += 1) {
        await addUser(`user${String(index)}`);
        await joinRoom(deps(), `user${String(index)}`, { inviteCode });
      }
      expect((await roomData(roomId)).memberCount).toBe(MAX_MEMBERS);

      await addUser("user21");
      await expectReason(joinRoom(deps(), "user21", { inviteCode }), "resource-exhausted", "room-full");
      const room = await roomData(roomId);
      expect(room.memberCount).toBe(MAX_MEMBERS);
      expect(room.memberIds).toHaveLength(MAX_MEMBERS);
      expect((await db.doc(`rooms/${roomId}/members/user21`).get()).exists).toBe(false);
    });

    it("19 人のルームに 2 人が同時に参加しても、20 人で止まる", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      for (let index = 2; index < MAX_MEMBERS; index += 1) {
        await addUser(`user${String(index)}`);
        await joinRoom(deps(), `user${String(index)}`, { inviteCode });
      }
      await addUser("late1");
      await addUser("late2");
      const results = await Promise.allSettled([
        joinRoom(deps(), "late1", { inviteCode }),
        joinRoom(deps(), "late2", { inviteCode }),
      ]);
      expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
      expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
      const room = await roomData(roomId);
      expect(room.memberCount).toBe(MAX_MEMBERS);
      expect((await db.collection(`rooms/${roomId}/members`).get()).size).toBe(MAX_MEMBERS);
    });

    it.each(["drawn", "closed"])("%s のルームには参加できない", async (status) => {
      const { roomId, inviteCode } = await aliceRoom();
      await db.doc(`rooms/${roomId}`).update({ status });
      await addUser("bob");
      await expectReason(joinRoom(deps(), "bob", { inviteCode }), "failed-precondition", "room-already-decided");
    });

    it("unlocked のルームには参加できる", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      await db.doc(`rooms/${roomId}`).update({ status: "unlocked" });
      await addUser("bob");
      await expect(joinRoom(deps(), "bob", { inviteCode })).resolves.toEqual({ roomId, alreadyMember: false });
    });

    it("表示名を登録していなければ参加できない", async () => {
      const { inviteCode } = await aliceRoom();
      await expectReason(joinRoom(deps(), "bob", { inviteCode }), "failed-precondition", "profile-required");
    });

    it("広告非表示の購入者は、購入済みのうち最初に参加した人", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      await addUser("bob", { adFree: true });
      await addUser("carol", { adFree: true });
      await joinRoom(deps(), "bob", { inviteCode });
      await joinRoom(deps(), "carol", { inviteCode });
      expect((await roomData(roomId)).adFreeSponsor).toEqual({ uid: "bob", displayName: "bob" });
    });
  });

  describe("leaveRoom・removeMember（02 の F-05）", () => {
    /** alice（作成者）・bob・carol のルームと、候補 3 件（c1・c2 に bob のいいね、c3 は bob の投稿） */
    async function roomWithLikes(): Promise<string> {
      const { roomId, inviteCode } = await aliceRoom();
      await addUser("bob");
      await addUser("carol");
      await joinRoom(deps(), "bob", { inviteCode });
      await joinRoom(deps(), "carol", { inviteCode });
      const room = db.doc(`rooms/${roomId}`);
      await room.collection("candidates").doc("c1").set({ postedBy: "alice", likedBy: ["bob", "carol"] });
      await room.collection("candidates").doc("c2").set({ postedBy: "carol", likedBy: ["bob"] });
      await room.collection("candidates").doc("c3").set({ postedBy: "bob", likedBy: ["alice"] });
      await room.collection("members").doc("bob").update({ ready: true });
      await room.update({
        readyCount: 1,
        "reroll.votesFor": FieldValue.arrayUnion("bob"),
        "reroll.votesAgainst": FieldValue.arrayUnion("carol"),
      });
      return roomId;
    }

    /** 候補の likedBy */
    async function likedBy(roomId: string, candidateId: string): Promise<unknown> {
      return (await db.doc(`rooms/${roomId}/candidates/${candidateId}`).get()).data()?.likedBy;
    }

    /** bob がいなくなったことを確かめる（いいねの除去・カウント・候補が残ること） */
    async function expectBobRemoved(roomId: string): Promise<void> {
      expect((await db.doc(`rooms/${roomId}/members/bob`).get()).exists).toBe(false);
      const room = await roomData(roomId);
      // readyCount は onMemberWrite（タスク 23）が数え直すので、退出・削除の Callable では変えない
      expect(room).toMatchObject({ memberIds: ["alice", "carol"], memberCount: 2, readyCount: 1 });
      expect(room.reroll).toMatchObject({ votesFor: [], votesAgainst: ["carol"] });
      expect(await likedBy(roomId, "c1")).toEqual(["carol"]);
      expect(await likedBy(roomId, "c2")).toEqual([]);
      // 退出した人の候補は残る（02 の F-05）
      expect(await likedBy(roomId, "c3")).toEqual(["alice"]);
    }

    it("退出すると、メンバー・カウント・その人のいいねが取り除かれ、候補は残る", async () => {
      const roomId = await roomWithLikes();
      await expect(leaveRoom(deps(), "bob", { roomId })).resolves.toEqual({});
      await expectBobRemoved(roomId);
    });

    it("作成者は退出できない", async () => {
      const roomId = await roomWithLikes();
      await expectReason(leaveRoom(deps(), "alice", { roomId }), "failed-precondition", "owner-cannot-leave");
      expect((await roomData(roomId)).memberCount).toBe(3);
    });

    it("メンバーでなければ退出できない・ルームが無ければ room-not-found", async () => {
      const roomId = await roomWithLikes();
      await expectReason(leaveRoom(deps(), "dave", { roomId }), "permission-denied", "not-room-member");
      await expectReason(leaveRoom(deps(), "bob", { roomId: "nothing" }), "not-found", "room-not-found");
    });

    it("作成者がメンバーを削除すると、退出と同じになる", async () => {
      const roomId = await roomWithLikes();
      await expect(removeMember(deps(), "alice", { roomId, memberId: "bob" })).resolves.toEqual({});
      await expectBobRemoved(roomId);
    });

    it("作成者以外はメンバーを削除できない", async () => {
      const roomId = await roomWithLikes();
      await expectReason(removeMember(deps(), "carol", { roomId, memberId: "bob" }), "permission-denied", "not-room-owner");
      expect((await roomData(roomId)).memberCount).toBe(3);
    });

    it("作成者は削除できない・メンバーでない人は member-not-found", async () => {
      const roomId = await roomWithLikes();
      await expectReason(
        removeMember(deps(), "alice", { roomId, memberId: "alice" }),
        "failed-precondition",
        "cannot-remove-owner",
      );
      await expectReason(removeMember(deps(), "alice", { roomId, memberId: "dave" }), "not-found", "member-not-found");
    });

    it("広告非表示の購入者が抜けたら、次に参加した購入者に移る", async () => {
      const { roomId, inviteCode } = await aliceRoom();
      await addUser("bob", { adFree: true });
      await addUser("carol");
      await addUser("dave", { adFree: true });
      for (const uid of ["bob", "carol", "dave"]) {
        await joinRoom(deps(), uid, { inviteCode });
      }
      expect((await roomData(roomId)).adFreeSponsor).toEqual({ uid: "bob", displayName: "bob" });

      await leaveRoom(deps(), "bob", { roomId });
      expect((await roomData(roomId)).adFreeSponsor).toEqual({ uid: "dave", displayName: "dave" });

      await removeMember(deps(), "alice", { roomId, memberId: "dave" });
      expect((await roomData(roomId)).adFreeSponsor).toBeNull();
    });
  });
});
