/**
 * 前回のメンバーへの招待（`inviteLastMembers`）と新しい候補のまとめ通知（`notifyNewCandidates`）を Emulator で確かめる（02 の §2.4・§8）。
 * Emulator には FCM が無いので、送った通知は `emulatorPushOutbox` に書かれる。そこを読んで「何を誰に送ったか」を確かめる。
 *
 * ほかのテストのファイルとデータが混ざらないよう、ルームの ID に `invite-`・`digest-` を付け、まとめる日は過去の決まった日にする
 * （ほかのテストが今の時刻で作った候補を数えない）。
 */
import type { App } from "firebase-admin/app";
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import type { ServiceDeps } from "../../functions/src/deps";
import { sendNewCandidateDigests } from "../../functions/src/digest/service";
import { inviteLastMembers } from "../../functions/src/invite/service";
import { EMULATOR_OUTBOX_COLLECTION, type PushMessage } from "../../functions/src/notifications/sender";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** まとめ通知を動かす時刻（2020-01-15 20:01 JST） */
const DIGEST_NOW_MS = Date.parse("2020-01-15T20:01:00+09:00");

describe("前回のメンバーへの招待と新しい候補のまとめ通知", () => {
  let app: App;
  let db: Firestore;

  function deps(nowMs: number = Date.now()): ServiceDeps {
    return { db, random: () => 0, nowMs: () => nowMs };
  }

  /** そのルームに送った通知（`type` で絞る） */
  async function outbox(roomId: string, type: string): Promise<PushMessage[]> {
    const snapshot = await db.collection(EMULATOR_OUTBOX_COLLECTION).where("threadId", "==", roomId).get();
    return snapshot.docs.map((doc) => doc.data() as PushMessage).filter((message) => message.data.type === type);
  }

  function tokensOf(messages: PushMessage[]): string[] {
    return messages.map((message) => message.token).sort();
  }

  /** ユーザーを作る（トークンは `<uid>-token`。`tokens: false` なら無し） */
  async function addUser(uid: string, tokens = true): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName: uid,
      avatarColor: AVATAR_COLORS[0],
      adFree: false,
      fcmTokens: tokens ? [`${uid}-token`] : [],
      createdAt: Timestamp.now(),
    });
  }

  /** ルームを作る（メンバーのドキュメントは `withMembers` の人だけ。終了したルームはメンバーのドキュメントを作らない） */
  async function addRoom(
    roomId: string,
    options: { name: string; status: string; memberIds: string[]; closedAtMs?: number; withMembers?: string[] },
  ): Promise<void> {
    await db.doc(`rooms/${roomId}`).set({
      name: options.name,
      ownerId: options.memberIds[0],
      inviteCode: "IVT2QQ",
      status: options.status,
      settings: { postLimit: 3, unlockRule: "all", deadlineAt: null, likeMode: "boost" },
      forcedUnlock: false,
      memberIds: options.memberIds,
      memberCount: options.memberIds.length,
      readyCount: 0,
      candidateCount: 0,
      adFreeSponsor: null,
      currentDrawId: null,
      winnerCandidateId: null,
      excludedCandidateIds: [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
      createdAt: Timestamp.now(),
      drawnAt: null,
      closedAt: options.closedAtMs === undefined ? null : Timestamp.fromMillis(options.closedAtMs),
    });
    for (const [index, uid] of (options.withMembers ?? []).entries()) {
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: uid === "me" ? "たくみ" : uid,
        avatarColor: AVATAR_COLORS[0],
        role: index === 0 ? "owner" : "member",
        ready: false,
        joinedAt: Timestamp.now(),
        lastSeenAt: Timestamp.now(),
      });
    }
  }

  async function addCandidate(roomId: string, id: string, postedBy: string, createdAtMs: number): Promise<void> {
    await db.doc(`rooms/${roomId}/candidates/${id}`).set({
      place: { name: id, area: "", latitude: 35, longitude: 139, mapItemId: null },
      category: "other",
      note: "",
      url: null,
      postedBy,
      postedByName: postedBy,
      colorIndex: 0,
      likedBy: [],
      fromPastIdeaId: null,
      createdAt: Timestamp.fromMillis(createdAtMs),
    });
  }

  function reasonOf(error: unknown): unknown {
    return error instanceof HttpsError ? (error.details as { reason?: unknown } | undefined)?.reason : error;
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("invite-digest"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("inviteLastMembers", () => {
    beforeEach(async () => {
      for (const uid of ["me", "haruka", "sota", "mio", "ken"]) {
        await addUser(uid, uid !== "mio");
      }
      // 直近の終了したルーム（me・haruka・sota・mio）と、もっと前の終了したルーム（me・ken）
      await addRoom("invite-prev", {
        name: "夏の日帰り",
        status: "closed",
        memberIds: ["me", "haruka", "sota", "mio"],
        closedAtMs: Date.now() - 86_400_000,
      });
      await addRoom("invite-older", { name: "冬", status: "closed", memberIds: ["me", "ken"], closedAtMs: Date.now() - 864_000_000 });
      // 今のルーム（me が作り、sota はもう参加している）
      await addRoom("invite-now", { name: "年末の旅行", status: "open", memberIds: ["me", "sota"], withMembers: ["me", "sota"] });
    });

    it("直近の終了したルームの、自分と今のメンバー以外に招待を送り、人数を返す", async () => {
      const result = await inviteLastMembers(deps(), "me", { roomId: "invite-now" });
      // haruka・mio（mio はトークンが無いので届かないが、招待した人数には数える）
      expect(result).toEqual({ invitedCount: 2 });
      const sent = await outbox("invite-now", "invited");
      expect(tokensOf(sent)).toEqual(["haruka-token"]);
      expect(sent[0]).toMatchObject({
        body: "たくみさんから「年末の旅行」に招待されました",
        data: { type: "invited", roomId: "invite-now", target: "join", inviteCode: "IVT2QQ" },
      });
    });

    it("同じ前回のルームからは 1 回だけ送り、2 回目は送らずに同じ人数を返す", async () => {
      await inviteLastMembers(deps(), "me", { roomId: "invite-now" });
      const again = await inviteLastMembers(deps(), "me", { roomId: "invite-now" });
      expect(again).toEqual({ invitedCount: 2 });
      expect(await outbox("invite-now", "invited")).toHaveLength(1);
    });

    it("送る途中で失敗したら印を消し、もう一度呼ぶと送れる", async () => {
      const failing = { db, sender: () => Promise.reject(new Error("FCM に繋がらない")) };
      await expect(inviteLastMembers(failing, "me", { roomId: "invite-now" })).rejects.toThrow("FCM に繋がらない");
      expect(await inviteLastMembers(deps(), "me", { roomId: "invite-now" })).toEqual({ invitedCount: 2 });
      expect(await outbox("invite-now", "invited")).toHaveLength(1);
    });

    it("終了したルームが無い・招待する人がいないなら、送らずに 0 を返す", async () => {
      await addRoom("invite-solo", { name: "ひとり", status: "open", memberIds: ["ken"], withMembers: ["ken"] });
      await db.doc("rooms/invite-older").delete();
      expect(await inviteLastMembers(deps(), "ken", { roomId: "invite-solo" })).toEqual({ invitedCount: 0 });
      // 前回のメンバーが全員もう今のルームにいる
      await db.doc("rooms/invite-now").update({ memberIds: ["me", "haruka", "sota", "mio"] });
      expect(await inviteLastMembers(deps(), "me", { roomId: "invite-now" })).toEqual({ invitedCount: 0 });
      expect(await outbox("invite-now", "invited")).toHaveLength(0);
    });

    it("メンバーでない・行き先が決まったルーム・無いルームは断る", async () => {
      await expect(inviteLastMembers(deps(), "ken", { roomId: "invite-now" }).catch(reasonOf)).resolves.toBe("not-room-member");
      await db.doc("rooms/invite-now").update({ status: "drawn" });
      await expect(inviteLastMembers(deps(), "me", { roomId: "invite-now" }).catch(reasonOf)).resolves.toBe("room-already-decided");
      await expect(inviteLastMembers(deps(), "me", { roomId: "invite-missing" }).catch(reasonOf)).resolves.toBe("room-not-found");
      await expect(inviteLastMembers(deps(), "me", {}).catch(reasonOf)).resolves.toBe("invalid-argument");
    });
  });

  describe("notifyNewCandidates", () => {
    const inWindow = DIGEST_NOW_MS - 3_600_000;
    const beforeWindow = DIGEST_NOW_MS - 2 * 86_400_000;

    beforeEach(async () => {
      for (const uid of ["alice", "bob", "carol"]) {
        await addUser(uid);
      }
      await addRoom("digest-open", { name: "年末の旅行", status: "open", memberIds: ["alice", "bob", "carol"] });
      await addRoom("digest-solo", { name: "週末のランチ", status: "unlocked", memberIds: ["alice", "bob"] });
      await addRoom("digest-drawn", { name: "春のお花見", status: "drawn", memberIds: ["alice", "bob"] });
      await addRoom("digest-old", { name: "前の候補だけ", status: "open", memberIds: ["alice", "bob"] });
      await addCandidate("digest-open", "c1", "alice", inWindow);
      await addCandidate("digest-open", "c2", "bob", inWindow);
      await addCandidate("digest-open", "c0", "carol", beforeWindow);
      await addCandidate("digest-solo", "c1", "alice", inWindow);
      await addCandidate("digest-drawn", "c1", "alice", inWindow);
      await addCandidate("digest-old", "c1", "alice", beforeWindow);
    });

    it("その日に候補が増えたルームのメンバーに N件を送る。自分の投稿しか増えていない人・決まったルームには送らない", async () => {
      const result = await sendNewCandidateDigests(deps(DIGEST_NOW_MS));
      expect(result).toEqual({ dateKey: "2020-01-15", candidates: 4, sentRooms: 2 });

      const open = await outbox("digest-open", "newCandidates");
      expect(tokensOf(open)).toEqual(["alice-token", "bob-token", "carol-token"]);
      expect(open[0]).toMatchObject({
        body: "「年末の旅行」に新しい候補が 2件増えました",
        data: { type: "newCandidates", roomId: "digest-open", target: "room" },
      });
      // alice の投稿だけなので alice には送らない
      expect(tokensOf(await outbox("digest-solo", "newCandidates"))).toEqual(["bob-token"]);
      expect(await outbox("digest-drawn", "newCandidates")).toHaveLength(0);
      expect(await outbox("digest-old", "newCandidates")).toHaveLength(0);
    });

    it("同じ日にもう一度動いても（やり直し・遅れ）、同じルームには 1 回だけ。次の日は送る", async () => {
      await sendNewCandidateDigests(deps(DIGEST_NOW_MS));
      const again = await sendNewCandidateDigests(deps(DIGEST_NOW_MS + 3_600_000));
      expect(again.sentRooms).toBe(0);
      expect(await outbox("digest-open", "newCandidates")).toHaveLength(3);

      await addCandidate("digest-open", "c3", "carol", DIGEST_NOW_MS + 3_600_000);
      const nextDay = await sendNewCandidateDigests(deps(DIGEST_NOW_MS + 86_400_000));
      expect(nextDay).toEqual({ dateKey: "2020-01-16", candidates: 1, sentRooms: 1 });
      expect(tokensOf(await outbox("digest-open", "newCandidates"))).toEqual([
        "alice-token",
        "alice-token",
        "bob-token",
        "bob-token",
        "carol-token",
      ]);
    });
  });
});
