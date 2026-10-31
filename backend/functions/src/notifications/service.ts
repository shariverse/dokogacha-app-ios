/**
 * プッシュ通知（02 の §8 F-60）を送る処理。解禁・抽選結果・引き直しの提案・途中の終了の呼び出し口
 * （`unlock/notify.ts`・`draw/notify.ts`・`reroll/notify.ts`・`close/notify.ts`）から呼ぶ。前回のメンバーへの招待（`invite/service.ts`）と
 * 新しい候補のまとめ（`digest/service.ts`）は、送る出来事を自分で作って `deliver` を呼ぶ。
 *
 * 1. ルーム（と抽選の記録・提案者のメンバー）を読んで、送る出来事（`PushEvent`）を作る
 * 2. 同じ通知を 2 回送らないよう、`rooms/{roomId}/notificationLog/{key}` を `create` する（もうあれば送らない。
 *    印を先に作るので、送る途中で落ちたときはやり直さない。2 回届くより 1 回届かない方を選ぶ）
 * 3. メンバーの `users/{uid}.fcmTokens` を読んで宛先を決め（`selectRecipients`）、送る
 * 4. 「登録されていない」で失敗したトークンを `users.fcmTokens` から外す
 *
 * 送る処理の失敗（読めない・FCM の失敗）は、ログに残すだけにして投げない（`notifyQuietly`）。
 * 通知は付け足しの機能で、元の Callable・トリガー（解禁・抽選・提案）を失敗させたり、トリガーをやり直させたりしない。
 */
import { FieldValue, Timestamp, type DocumentReference, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

import type { DrawDoc, MemberDoc, RoomDoc } from "../domain/models";
import { drawsRef, membersRef, roomRef, userRef } from "../paths";
import {
  audienceOf,
  excludedRecipient,
  notificationLogKey,
  pushBody,
  pushData,
  selectRecipients,
  unregisteredTokensByUser,
  type PushEvent,
  type PushEventKind,
} from "./logic";
import { defaultPushSender, type PushSender } from "./sender";

/** 通知を送るのに使う外部のもの（`ServiceDeps` をそのまま渡せる） */
export interface NotificationDeps {
  /** Firestore（Admin SDK） */
  db: Firestore;
  /** 送り方（省略すると `defaultPushSender`。テストで差し替える） */
  sender?: PushSender;
}

/** 送った結果（ログとテストで使う） */
export type NotificationOutcome =
  /** 送る出来事が作れなかった（ルーム・抽選の記録・提案者が無い） */
  | { kind: "skipped"; reason: string }
  /** もう送ってあった（印があった） */
  | { kind: "alreadySent" }
  /** 送った（宛先が 0 件のときも） */
  | { kind: "sent"; recipients: number; succeeded: number; removedTokens: number };

/** 通知を送る印のコレクション（`rooms/{roomId}/notificationLog`。クライアントからは読めない。ルールの最後の match で拒否） */
export const NOTIFICATION_LOG_COLLECTION = "notificationLog";

/** Firestore の `create` が「もうある」で失敗したときのコード（gRPC の ALREADY_EXISTS） */
const ALREADY_EXISTS = 6;

/**
 * ルームが解禁されたことを、メンバー全員に送る（ルームにつき 1 回）。
 * @param deps 外部のもの
 * @param roomId ルームの ID
 */
export async function sendRoomUnlocked(deps: NotificationDeps, roomId: string): Promise<NotificationOutcome> {
  const room = await readRoom(deps.db, roomId);
  if (room === null) {
    return { kind: "skipped", reason: "room-not-found" };
  }
  return deliver(deps, room, { kind: "unlocked", roomId, roomName: room.name });
}

/**
 * 行き先が決まったことを、回した人以外に送る（抽選ごとに 1 回）。
 * @param deps 外部のもの
 * @param roomId ルームの ID
 * @param drawId 抽選の ID（回した人 `drawnBy` はここから読む）
 */
export async function sendRoomDrawn(deps: NotificationDeps, roomId: string, drawId: string): Promise<NotificationOutcome> {
  const room = await readRoom(deps.db, roomId);
  if (room === null) {
    return { kind: "skipped", reason: "room-not-found" };
  }
  const draw = (await drawsRef(roomRef(deps.db, roomId)).doc(drawId).get()).data() as Partial<DrawDoc> | undefined;
  if (typeof draw?.drawnBy !== "string") {
    return { kind: "skipped", reason: "draw-not-found" };
  }
  return deliver(deps, room, { kind: "drawn", roomId, roomName: room.name, drawId, drawnBy: draw.drawnBy });
}

/**
 * 引き直しが提案されたことを、提案者以外に送る（ルームにつき 1 回）。
 * @param deps 外部のもの
 * @param roomId ルームの ID
 * @param proposedBy 提案した人の uid（文面の {名前} はルームのメンバーの表示名）
 */
export async function sendRerollProposed(
  deps: NotificationDeps,
  roomId: string,
  proposedBy: string,
): Promise<NotificationOutcome> {
  const room = await readRoom(deps.db, roomId);
  if (room === null) {
    return { kind: "skipped", reason: "room-not-found" };
  }
  const member = (await membersRef(roomRef(deps.db, roomId)).doc(proposedBy).get()).data() as Partial<MemberDoc> | undefined;
  if (typeof member?.displayName !== "string") {
    return { kind: "skipped", reason: "proposer-not-found" };
  }
  return deliver(deps, room, {
    kind: "rerollProposed",
    roomId,
    drawId: room.currentDrawId ?? null,
    proposedBy,
    proposerName: member.displayName,
  });
}

/**
 * 作成者がルームを途中で終了したことを、作成者以外のメンバーに送る（ルームにつき 1 回。Discussion #155 の Q5）。
 * 宛先は終了した後のルームの `memberIds`（終了しても `memberIds` は変わらないので、終了したときのメンバー）。
 * @param deps 外部のもの
 * @param roomId ルームの ID
 * @param endedBy 終了した人（作成者）の uid（文面の {作成者} はルームのメンバーの表示名）
 */
export async function sendRoomEnded(deps: NotificationDeps, roomId: string, endedBy: string): Promise<NotificationOutcome> {
  const room = await readRoom(deps.db, roomId);
  if (room === null) {
    return { kind: "skipped", reason: "room-not-found" };
  }
  const member = (await membersRef(roomRef(deps.db, roomId)).doc(endedBy).get()).data() as Partial<MemberDoc> | undefined;
  if (typeof member?.displayName !== "string") {
    return { kind: "skipped", reason: "owner-not-found" };
  }
  return deliver(deps, room, { kind: "roomEnded", roomId, roomName: room.name, endedBy, ownerName: member.displayName });
}

/**
 * 送る処理を、失敗しても投げずにログに残すだけにして呼ぶ（呼び出し口から使う）。
 * @param kind 通知の種類（ログ用）
 * @param context ログに添える値
 * @param send 送る処理
 */
export async function notifyQuietly(
  kind: PushEventKind,
  context: Record<string, string>,
  send: () => Promise<NotificationOutcome>,
): Promise<void> {
  try {
    const outcome = await send();
    logger.info("プッシュ通知を処理した", { notification: kind, ...context, outcome });
  } catch (error) {
    logger.error("プッシュ通知を送れなかった（元の処理は失敗にしない）", {
      notification: kind,
      ...context,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

/** ルームを読む（名前とメンバーが要る。無ければ null） */
async function readRoom(db: Firestore, roomId: string): Promise<Pick<RoomDoc, "name" | "memberIds" | "currentDrawId"> | null> {
  const room = (await roomRef(db, roomId).get()).data() as Partial<RoomDoc> | undefined;
  if (typeof room?.name !== "string" || !Array.isArray(room.memberIds)) {
    return null;
  }
  return { name: room.name, memberIds: room.memberIds, currentDrawId: room.currentDrawId ?? null };
}

/**
 * 印を作れたら、宛先（`audienceOf`。ふつうはルームのメンバー、招待なら招待した人たち）のトークンに送り、無効なトークンを外す。
 * 前回のメンバーへの招待（`invite/service.ts`）・新しい候補のまとめ（`digest/service.ts`）からも使う。
 * @param deps 外部のもの
 * @param room ルーム（メンバー）
 * @param event 送る出来事
 * @param logFields 印に一緒に書く値（招待した人数など。同じ印で 2 回目に呼ばれたときに読み返す）
 */
export async function deliver(
  deps: NotificationDeps,
  room: Pick<RoomDoc, "memberIds">,
  event: PushEvent,
  logFields: Record<string, unknown> = {},
): Promise<NotificationOutcome> {
  if (!(await claim(deps.db, event, logFields))) {
    return { kind: "alreadySent" };
  }
  const audience = audienceOf(event, room.memberIds);
  const users = audience.length === 0 ? [] : await deps.db.getAll(...audience.map((uid) => userRef(deps.db, uid)));
  const recipients = selectRecipients(
    audience,
    excludedRecipient(event),
    users.map((snapshot) => ({ uid: snapshot.id, fcmTokens: (snapshot.data() as { fcmTokens?: unknown } | undefined)?.fcmTokens })),
  );
  if (recipients.length === 0) {
    return { kind: "sent", recipients: 0, succeeded: 0, removedTokens: 0 };
  }
  const body = pushBody(event);
  const data = pushData(event);
  const sender = deps.sender ?? defaultPushSender(deps.db);
  const results = await sender(recipients.map(({ token }) => ({ token, body, data, threadId: event.roomId })));
  const unregistered = unregisteredTokensByUser(recipients, results);
  // 無効なトークンを外す（`onUserProfileUpdate` はトークンだけの更新では何もしない）
  await Promise.all(
    [...unregistered].map(([uid, tokens]) => userRef(deps.db, uid).update({ fcmTokens: FieldValue.arrayRemove(...tokens) })),
  );
  return {
    kind: "sent",
    recipients: recipients.length,
    succeeded: results.filter((result) => result.success).length,
    removedTokens: [...unregistered.values()].reduce((sum, tokens) => sum + tokens.length, 0),
  };
}

/**
 * 送る印のドキュメント（`rooms/{roomId}/notificationLog/{key}`）。
 * @param db Firestore
 * @param event 送る出来事
 */
export function notificationLogRef(db: Firestore, event: PushEvent): DocumentReference {
  return roomRef(db, event.roomId).collection(NOTIFICATION_LOG_COLLECTION).doc(notificationLogKey(event));
}

/**
 * 送る印を作る。もうあれば false（送らない）。
 * @param db Firestore
 * @param event 送る出来事
 * @param logFields 印に一緒に書く値
 */
async function claim(db: Firestore, event: PushEvent, logFields: Record<string, unknown>): Promise<boolean> {
  try {
    await notificationLogRef(db, event).create({
      ...logFields,
      kind: event.kind,
      sentAt: Timestamp.now(),
    });
    return true;
  } catch (error) {
    if ((error as { code?: unknown }).code === ALREADY_EXISTS) {
      return false;
    }
    throw error;
  }
}
