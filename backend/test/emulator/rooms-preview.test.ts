/**
 * 参加前の確認（previewRoom。03 の S-06）を、Emulator の Firestore に対して直接呼んで確かめる。
 * 断る理由は joinRoom と同じ（存在しないコード・満員・決定後）で、何も書き込まないことも確かめる。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";
import type { App } from "firebase-admin/app";

import { AVATAR_COLORS } from "../../functions/src/domain/avatarPalette";
import { MAX_MEMBERS } from "../../functions/src/domain/constants";
import { cryptoRandomInt } from "../../functions/src/domain/random";
import type { ServiceDeps } from "../../functions/src/deps";
import { createRoom, joinRoom, previewRoom } from "../../functions/src/rooms/service";
import { clearFirestore, closeAdmin, openAdmin } from "./firestore-admin";

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, code: string, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code, details: { reason } });
}

const roomInput = { name: "夏の花火大会", postLimit: 3, unlockRule: "all", likeMode: "boost" };

describe("previewRoom（Emulator の Firestore）", () => {
  let app: App;
  let db: Firestore;

  function deps(): ServiceDeps {
    return { db, random: cryptoRandomInt, nowMs: () => Date.now() };
  }

  /** プロフィールを直接作る（saveProfile を通さずに速く用意する。表示名は既定で uid） */
  async function addUser(uid: string, displayName = uid): Promise<void> {
    await db.doc(`users/${uid}`).set({
      displayName,
      avatarColor: AVATAR_COLORS[0],
      adFree: false,
      fcmTokens: [],
      createdAt: Timestamp.now(),
    });
  }

  /** はるかが作ったルームと招待コード */
  async function harukaRoom(): Promise<{ roomId: string; inviteCode: string }> {
    await addUser("haruka", "はるか");
    return createRoom(deps(), "haruka", roomInput);
  }

  /** ルームとその下のドキュメントの数（書き込んでいないことを確かめる） */
  async function snapshot(roomId: string): Promise<{ room: unknown; members: number }> {
    const room = (await db.doc(`rooms/${roomId}`).get()).data();
    const members = (await db.collection(`rooms/${roomId}/members`).get()).size;
    return { room, members };
  }

  beforeAll(() => {
    ({ app, db } = openAdmin("rooms-preview"));
  });

  beforeEach(async () => {
    await clearFirestore();
  });

  afterAll(async () => {
    await clearFirestore();
    await closeAdmin(app);
  });

  it("ルーム名・作成者名・メンバー数・候補数・状態を返し、何も書き込まない", async () => {
    const { roomId, inviteCode } = await harukaRoom();
    await db.doc(`rooms/${roomId}`).update({ candidateCount: 2 });
    const before = await snapshot(roomId);

    await expect(previewRoom(deps(), "bob", { inviteCode })).resolves.toEqual({
      roomId,
      name: "夏の花火大会",
      ownerName: "はるか",
      memberCount: 1,
      candidateCount: 2,
      status: "open",
      alreadyMember: false,
    });
    expect(await snapshot(roomId)).toEqual(before);
  });

  it("小文字・ハイフン・全角・空白の入力も正規化して引く", async () => {
    const { roomId, inviteCode } = await harukaRoom();
    // 全角の英数字（U+FF01〜）は半角の文字の番号に 0xFEE0 を足したもの
    const fullWidth = inviteCode
      .toLowerCase()
      .replace(/[0-9a-z]/gu, (character) => String.fromCharCode(character.charCodeAt(0) + 0xfee0));
    for (const input of [`${inviteCode.slice(0, 3)}-${inviteCode.slice(3)}`.toLowerCase(), ` ${fullWidth}\u3000`]) {
      await expect(previewRoom(deps(), "bob", { inviteCode: input })).resolves.toMatchObject({ roomId });
    }
  });

  it("存在しない・形が正しくないコードは「招待コードが見つかりません」、文字列でなければ invalid-argument", async () => {
    await harukaRoom();
    await expectReason(previewRoom(deps(), "bob", { inviteCode: "ZZZZZZ" }), "not-found", "invite-code-not-found");
    await expectReason(previewRoom(deps(), "bob", { inviteCode: "DK7-290" }), "not-found", "invite-code-not-found");
    await expectReason(previewRoom(deps(), "bob", { inviteCode: 123 }), "invalid-argument", "invalid-argument");
  });

  it("招待コードが残っていてもルームが無ければ「招待コードが見つかりません」", async () => {
    const { roomId, inviteCode } = await harukaRoom();
    await db.doc(`rooms/${roomId}`).delete();
    await expectReason(previewRoom(deps(), "bob", { inviteCode }), "not-found", "invite-code-not-found");
  });

  it("20 人のルームは「満員」（joinRoom と同じ理由）", async () => {
    const { roomId, inviteCode } = await harukaRoom();
    await db.doc(`rooms/${roomId}`).update({ memberCount: MAX_MEMBERS });
    await expectReason(previewRoom(deps(), "bob", { inviteCode }), "resource-exhausted", "room-full");
  });

  it.each(["drawn", "closed"])("%s のルームは「もう行き先が決まっています」", async (status) => {
    const { roomId, inviteCode } = await harukaRoom();
    await db.doc(`rooms/${roomId}`).update({ status, memberCount: MAX_MEMBERS });
    await expectReason(previewRoom(deps(), "bob", { inviteCode }), "failed-precondition", "room-already-decided");
  });

  it("すでにメンバーなら、決定後・満員でも alreadyMember を返す（S-06 を出さずにルームへ）", async () => {
    const { roomId, inviteCode } = await harukaRoom();
    await addUser("bob", "ぼぶ");
    await joinRoom(deps(), "bob", { inviteCode });
    await db.doc(`rooms/${roomId}`).update({ status: "drawn", memberCount: MAX_MEMBERS });

    await expect(previewRoom(deps(), "bob", { inviteCode })).resolves.toMatchObject({
      roomId,
      status: "drawn",
      alreadyMember: true,
    });
    await expect(previewRoom(deps(), "haruka", { inviteCode })).resolves.toMatchObject({ alreadyMember: true });
  });

  it("表示名を登録していなくても確かめられる（参加は joinRoom が断る）", async () => {
    const { inviteCode } = await harukaRoom();
    await expect(previewRoom(deps(), "nobody", { inviteCode })).resolves.toMatchObject({ alreadyMember: false });
    await expectReason(joinRoom(deps(), "nobody", { inviteCode }), "failed-precondition", "profile-required");
  });
});
