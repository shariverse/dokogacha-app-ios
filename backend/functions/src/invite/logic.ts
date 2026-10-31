/**
 * 前回のメンバーへの招待（02 の §2.4 F-04「前回のメンバーを招待」・§8・05 の §5 の `inviteLastMembers`）の判定
 * （Firestore に触れない純粋な関数）。Firestore の読み書きと送るのは `service.ts` が行う。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Invite.swift`）と、S-04 のボタンの人数
 * （`Dokogacha/Domain/Logic/LastMembersInvitation.swift`）も同じ規則で決める。片方を変えたら両方を変える。
 */
import type { RoomDoc } from "../domain/models";
import { appError } from "../errors";

/** 判定に使う今のルームの値 */
export type InvitingRoom = Pick<RoomDoc, "status"> & Partial<Pick<RoomDoc, "memberIds">>;

/**
 * 今のルームから前回のメンバーを招待できるか確かめる。順に確かめる:
 * 1. 呼んだ人が今のルームのメンバー（`memberIds` にいる。いなければ `not-room-member`）。
 *    作成者に限らない（02 の §2.4 は「自分が参加した直近の closed ルームのメンバー」とだけあり、作成者だけとは書いていない。
 *    ボタンは S-04 にあり、S-04 はルームを作った直後と、S-07 のアバターの並びの招待の「＋」（メンバー全員に出す）から開く）
 * 2. 今のルームが参加できる状態（`open`・`unlocked`。02 の §2.4 の参加条件。`drawn`・`closed` は `room-already-decided`。
 *    招待しても参加できないルームには送らない）
 * @param room 今のルーム
 * @param uid 呼んだ人
 * @throws `not-room-member`・`room-already-decided`
 */
export function assertCanInvite(room: InvitingRoom, uid: string): void {
  if (!Array.isArray(room.memberIds) || !room.memberIds.includes(uid)) {
    throw appError("not-room-member");
  }
  if (room.status !== "open" && room.status !== "unlocked") {
    throw appError("room-already-decided");
  }
}

/**
 * 招待する人を決める（02 の §2.4「直近の closed ルームのメンバー（自分以外）」）。
 * - 前回のルームの終了したときのメンバー（`memberIds`）から、自分と、今のルームにもういる人を外す（もう参加している人に招待を送らない）
 * - 同じ人は 1 回だけ。前回のルームの並び（参加の順）を保つ
 * @param previousMemberIds 前回のルームのメンバー
 * @param currentMemberIds 今のルームのメンバー
 * @param uid 呼んだ人
 * @returns 招待する人の uid
 */
export function lastMembersInvitees(
  previousMemberIds: readonly string[],
  currentMemberIds: readonly string[],
  uid: string,
): string[] {
  const skipped = new Set([uid, ...currentMemberIds]);
  const invitees: string[] = [];
  for (const memberId of previousMemberIds) {
    if (!skipped.has(memberId)) {
      skipped.add(memberId);
      invitees.push(memberId);
    }
  }
  return invitees;
}
