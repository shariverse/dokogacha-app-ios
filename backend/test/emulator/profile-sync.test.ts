/**
 * プロフィールの変更を参加中のルームの複製に反映する処理（05 の §5 の `onUserProfileUpdate`）を Emulator で確かめる。
 * - 処理（`syncProfileCopies`）を Admin SDK で直接呼び、反映する範囲・冪等・ルームが多いときを確かめる
 * - Functions の Emulator で動くトリガーが、`users/{uid}` の更新から複製を書き換えることを確かめる
 *   （トリガーは非同期に動くので、条件を満たすまで短い間隔で読み直し、上限の時間で打ち切る）
 *
 * ほかのテストのファイルとデータが混ざらないよう、uid とルームの ID に `sync-` を付ける。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { PROFILE_SYNC_PARALLEL_ROOMS, syncProfileCopies } from "../../functions/src/users/profileSync";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** 複製を書き換える人 */
const ME = "sync-alice";
/** ほかのメンバー */
const OTHER = "sync-bob";

/** トリガーの反映を待つ上限（Functions の Emulator の初回の読み込みを含む） */
const TRIGGER_TIMEOUT_MS = 20_000;
/** トリガーの反映を読み直す間隔 */
const POLL_INTERVAL_MS = 200;

/**
 * `read` が true を返すまで、`POLL_INTERVAL_MS` ごとに読み直す。`TRIGGER_TIMEOUT_MS` を過ぎたら失敗する。
 * 固定の時間で待たずに、反映が済んだ時点で次へ進む。
 */
async function waitUntil(description: string, read: () => Promise<boolean>): Promise<void> {
  const deadline = Date.now() + TRIGGER_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (await read()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }
  throw new Error(`${String(TRIGGER_TIMEOUT_MS)}ms 待っても ${description}`);
}

describe("プロフィールの複製の反映（onUserProfileUpdate）", () => {
  let app: App;
  let db: Firestore;

  /** プロフィールを作る（作成なのでトリガーは動かない） */
  async function addUser(uid: string, displayName: string, avatarColor: string = AVATAR_COLORS[0]): Promise<void> {
    await db.doc(`users/${uid}`).set({ displayName, avatarColor, adFree: false, fcmTokens: [], createdAt: Timestamp.now() });
  }

  /**
   * ルームを作る。`members` のメンバーと、`posts` の候補（投稿者の uid）を、表示名 `copyName` の複製で入れる。
   * `memberIds` は `memberIds` を渡せば上書きする（退出した後の状態を作る）
   */
  async function addRoom(
    roomId: string,
    options: {
      members?: string[];
      memberIds?: string[];
      posts?: string[];
      copyName?: string;
      sponsor?: string | null;
      status?: string;
    } = {},
  ): Promise<void> {
    const members = options.members ?? [ME, OTHER];
    const copyName = options.copyName ?? "まえ";
    const nameOf = (uid: string) => (uid === ME ? copyName : uid);
    await db.doc(`rooms/${roomId}`).set({
      name: "年末の旅行",
      ownerId: members[0],
      status: options.status ?? "open",
      memberIds: options.memberIds ?? members,
      memberCount: members.length,
      adFreeSponsor: options.sponsor ? { uid: options.sponsor, displayName: nameOf(options.sponsor) } : null,
      createdAt: Timestamp.now(),
    });
    for (const uid of members) {
      await db.doc(`rooms/${roomId}/members/${uid}`).set({
        displayName: nameOf(uid),
        avatarColor: AVATAR_COLORS[0],
        role: uid === members[0] ? "owner" : "member",
        ready: false,
        joinedAt: Timestamp.now(),
        lastSeenAt: Timestamp.now(),
      });
    }
    for (const [index, uid] of (options.posts ?? [ME, OTHER]).entries()) {
      await db.doc(`rooms/${roomId}/candidates/c${String(index)}`).set({
        postedBy: uid,
        postedByName: nameOf(uid),
        likedBy: [],
        colorIndex: index,
        createdAt: Timestamp.now(),
      });
    }
  }

  async function field(path: string, name: string): Promise<unknown> {
    return (await db.doc(path).get()).get(name);
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("profile-sync"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  describe("syncProfileCopies（処理を直接呼ぶ）", () => {
    it("参加中のルームのメンバー・自分の候補の投稿者名・広告の購入者を今の名前と色にし、ほかの人の複製は変えない", async () => {
      await addUser(ME, "あと", AVATAR_COLORS[3]);
      await addRoom("sync-room", { sponsor: ME });

      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: 1, writes: 3 });

      expect((await db.doc(`rooms/sync-room/members/${ME}`).get()).data()).toMatchObject({
        displayName: "あと",
        avatarColor: AVATAR_COLORS[3],
        role: "owner",
      });
      expect(await field("rooms/sync-room/candidates/c0", "postedByName")).toBe("あと");
      expect(await field("rooms/sync-room", "adFreeSponsor")).toEqual({ uid: ME, displayName: "あと" });
      // ほかのメンバーとその候補はそのまま
      expect(await field(`rooms/sync-room/members/${OTHER}`, "displayName")).toBe(OTHER);
      expect(await field("rooms/sync-room/candidates/c1", "postedByName")).toBe(OTHER);
    });

    it("2 回目は何も書かない（冪等）", async () => {
      await addUser(ME, "あと");
      await addRoom("sync-room");
      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: 1, writes: 2 });
      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: 1, writes: 0 });
      expect(await field(`rooms/sync-room/members/${ME}`, "displayName")).toBe("あと");
    });

    it("終了したルームにも反映し、退出したルーム（memberIds にいない）には書かない", async () => {
      await addUser(ME, "あと");
      await addRoom("sync-closed", { status: "closed" });
      // 退出の後に members のドキュメントだけが残っていても、memberIds にいなければ参加中ではない
      await addRoom("sync-left", { memberIds: [OTHER] });

      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: 1, writes: 2 });
      expect(await field(`rooms/sync-closed/members/${ME}`, "displayName")).toBe("あと");
      expect(await field(`rooms/sync-left/members/${ME}`, "displayName")).toBe("まえ");
      expect(await field("rooms/sync-left/candidates/c0", "postedByName")).toBe("まえ");
    });

    it("参加中のルームが多くても、すべてのルームに反映する（並べて処理する数を超える）", async () => {
      const count = PROFILE_SYNC_PARALLEL_ROOMS * 2 + 3;
      await addUser(ME, "あと");
      for (let index = 0; index < count; index += 1) {
        await addRoom(`sync-many-${String(index)}`, { posts: [ME] });
      }

      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: count, writes: count * 2 });
      const members = await db.collectionGroup("members").get();
      const mine = members.docs.filter((doc) => doc.id === ME);
      expect(mine).toHaveLength(count);
      expect(mine.every((doc) => doc.get("displayName") === "あと")).toBe(true);
    });

    it("プロフィールが無い（削除された）なら何も書かない", async () => {
      await addRoom("sync-room");
      await expect(syncProfileCopies(db, ME)).resolves.toEqual({ rooms: 1, writes: 0 });
      expect(await field(`rooms/sync-room/members/${ME}`, "displayName")).toBe("まえ");
    });
  });

  describe("onUserProfileUpdate（Functions の Emulator のトリガー）", () => {
    it(
      "users/{uid} の表示名を変えると、参加中のルームの複製が新しい名前になる",
      async () => {
        await addUser(ME, "まえ");
        await addRoom("sync-trigger-1");
        await addRoom("sync-trigger-2", { posts: [OTHER] });

        await db.doc(`users/${ME}`).update({ displayName: "あと" });

        await waitUntil("トリガーがメンバーと候補の複製を書き換えない", async () => {
          const names = await Promise.all([
            field(`rooms/sync-trigger-1/members/${ME}`, "displayName"),
            field(`rooms/sync-trigger-2/members/${ME}`, "displayName"),
            field("rooms/sync-trigger-1/candidates/c0", "postedByName"),
          ]);
          return names.every((name) => name === "あと");
        });
        // ほかの人の複製は変えない
        expect(await field(`rooms/sync-trigger-1/members/${OTHER}`, "displayName")).toBe(OTHER);
        expect(await field("rooms/sync-trigger-2/candidates/c0", "postedByName")).toBe(OTHER);
      },
      TRIGGER_TIMEOUT_MS * 2,
    );

    it(
      "続けて表示名を変えても、最後の名前にそろう",
      async () => {
        await addUser(ME, "まえ");
        await addRoom("sync-trigger-1");

        await db.doc(`users/${ME}`).update({ displayName: "つぎ" });
        await db.doc(`users/${ME}`).update({ displayName: "さいご" });

        await waitUntil("トリガーが最後の名前にそろえない", async () => {
          const names = await Promise.all([
            field(`rooms/sync-trigger-1/members/${ME}`, "displayName"),
            field("rooms/sync-trigger-1/candidates/c0", "postedByName"),
          ]);
          return names.every((name) => name === "さいご");
        });
      },
      TRIGGER_TIMEOUT_MS * 2,
    );
  });
});
