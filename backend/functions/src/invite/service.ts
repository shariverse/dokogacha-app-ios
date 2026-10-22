/**
 * 前回のメンバーへの招待（`inviteLastMembers`。02 の §2.4 F-04・§8）。
 *
 * 1. 今のルームを読み、呼んだ人がメンバーで、参加できる状態か確かめる（`assertCanInvite`）
 * 2. 呼んだ人が参加した直近の `closed` のルームを探す（`memberIds array-contains uid`・`status == closed`・`closedAt` の降順で 1 件。
 *    `firestore.indexes.json` の `memberIds`＋`status`＋`closedAt` の索引。ホームの思い出のきっぷと同じクエリ）
 * 3. 招待する人を決め（`lastMembersInvitees`）、その人たちのトークンに「{名前}さんから「{ルーム名}」に招待されました」を送る。
 *    ペイロードに招待コードを入れ、通知を開くと S-06 参加確認が開く（招待リンクと同じ道）
 *
 * 同じ人が同じ前回のルームから招待するのは 1 回だけ（`notificationLog` の `invited-{uid}-{前回のルームの ID}`）。
 * 2 回目からは送らずに、1 回目に招待した人数を返す（連打・やり直しで同じ人たちに何度も送らない。アプリはトーストを同じ人数で出す）。
 * 送る途中で失敗したら印を消してから投げる（この Callable は招待を送ることそのものなので、もう一度押せば送り直せるようにする）。
 */
import type { Firestore } from "firebase-admin/firestore";

import type { MemberDoc, RoomDoc } from "../domain/models";
import { appError } from "../errors";
import type { PushEvent } from "../notifications/logic";
import { deliver, notificationLogRef, type NotificationDeps } from "../notifications/service";
import { membersRef, roomRef } from "../paths";
import { parseRoomIdInput } from "../unlock/input";
import { assertCanInvite, lastMembersInvitees } from "./logic";

/** `inviteLastMembers` の結果（アプリの `InviteLastMembersResponse`） */
export interface InviteLastMembersResult {
  /** 招待した人数（前回のルームが無い・招待する人がいなければ 0） */
  invitedCount: number;
}

/** 印に書く、招待した人数のフィールド */
const INVITED_COUNT_FIELD = "invitedCount";

/**
 * 呼んだ人が参加した直近の `closed` のルーム（無ければ null）。
 * @param db Firestore
 * @param uid 呼んだ人
 */
export async function latestClosedRoom(db: Firestore, uid: string): Promise<{ id: string; memberIds: string[] } | null> {
  const snapshot = await db
    .collection("rooms")
    .where("memberIds", "array-contains", uid)
    .where("status", "==", "closed")
    .orderBy("closedAt", "desc")
    .limit(1)
    .get();
  const doc = snapshot.docs[0];
  if (doc === undefined) {
    return null;
  }
  const memberIds = (doc.data() as Partial<RoomDoc>).memberIds;
  return { id: doc.id, memberIds: Array.isArray(memberIds) ? memberIds : [] };
}

/**
 * 前回のメンバーを今のルームに招待する（`inviteLastMembers` の中身）。
 * @param deps 外部のもの（`ServiceDeps` をそのまま渡せる。`sender` を足すと送り方を差し替えられる。テスト用）
 * @param uid 呼んだ人（今のルームのメンバー）
 * @param data `request.data`（`{ roomId }`。今のルーム）
 * @returns 招待した人数
 * @throws `invalid-argument`・`room-not-found`・`not-room-member`・`room-already-decided`
 */
export async function inviteLastMembers(
  deps: NotificationDeps,
  uid: string,
  data: unknown,
): Promise<InviteLastMembersResult> {
  const { roomId } = parseRoomIdInput(data);
  const ref = roomRef(deps.db, roomId);
  const room = (await ref.get()).data() as RoomDoc | undefined;
  if (room === undefined) {
    throw appError("room-not-found");
  }
  assertCanInvite(room, uid);
  const inviter = (await membersRef(ref).doc(uid).get()).data() as Partial<MemberDoc> | undefined;
  if (typeof inviter?.displayName !== "string") {
    throw appError("not-room-member");
  }
  const previous = await latestClosedRoom(deps.db, uid);
  if (previous === null) {
    return { invitedCount: 0 };
  }
  const inviteeIds = lastMembersInvitees(previous.memberIds, room.memberIds, uid);
  if (inviteeIds.length === 0) {
    return { invitedCount: 0 };
  }
  const event: PushEvent = {
    kind: "invited",
    roomId,
    roomName: room.name,
    inviteCode: room.inviteCode,
    inviterId: uid,
    inviterName: inviter.displayName,
    sourceRoomId: previous.id,
    inviteeIds,
  };
  try {
    const outcome = await deliver(deps, room, event, { [INVITED_COUNT_FIELD]: inviteeIds.length, sourceRoomId: previous.id });
    if (outcome.kind === "alreadySent") {
      const logged = (await notificationLogRef(deps.db, event).get()).data()?.[INVITED_COUNT_FIELD] as unknown;
      return { invitedCount: typeof logged === "number" ? logged : inviteeIds.length };
    }
  } catch (error) {
    // 印だけ残って送れていない状態にしない（もう一度押せば送り直せる）
    await notificationLogRef(deps.db, event).delete();
    throw error;
  }
  return { invitedCount: inviteeIds.length };
}
