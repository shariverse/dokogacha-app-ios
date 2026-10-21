/**
 * ルームの作成・参加・退出・メンバー削除の判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `service.ts` が行い、判定はここに切り出して Jest で確かめる。
 */
import { MAX_MEMBERS } from "../domain/constants";
import { generateInviteCode } from "../domain/inviteCode";
import {
  initialRerollState,
  type AdFreeSponsor,
  type MemberDoc,
  type MemberRole,
  type RoomDoc,
  type RoomStatus,
} from "../domain/models";
import type { RandomInt } from "../domain/random";
import { appError } from "../errors";
import type { CreateRoomInput } from "./input";

/**
 * 招待コードを作り直す最大の回数。
 * 32 文字 × 6 桁で約 10 億通りあるので、重複が 10 回続くことはまず無い（続いたら `invite-code-unavailable`）。
 */
export const MAX_INVITE_CODE_ATTEMPTS = 10;

/**
 * 招待コードを作り、`tryReserve` で確保できるまで作り直す（05 の §3「コード重複時は再生成」）。
 * `tryReserve` は、そのコードが未使用なら確保して true、使用済みなら false を返す（`inviteCodes/{code}` のトランザクション）。
 * @param tryReserve コードを確保する関数
 * @param random 乱数（テストでは重複を再現するために固定の並びを渡す）
 * @param maxAttempts 作る最大の回数
 * @returns 確保したコード
 * @throws `invite-code-unavailable`（すべて重複したとき）
 */
export async function allocateInviteCode(
  tryReserve: (code: string) => Promise<boolean>,
  random: RandomInt,
  maxAttempts: number = MAX_INVITE_CODE_ATTEMPTS,
): Promise<string> {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const code = generateInviteCode(random);
    if (await tryReserve(code)) {
      return code;
    }
  }
  throw appError("invite-code-unavailable");
}

/** 参加の判定に要るルームの値 */
export type JoinableRoom = Pick<RoomDoc, "status" | "memberCount">;

/** 参加できる状態（02 の F-04「ルームが open または unlocked」） */
const JOINABLE_STATUSES: readonly RoomStatus[] = ["open", "unlocked"];

/**
 * まだメンバーでない人がルームに参加できるか確かめる（02 の F-04 の参加条件）。
 * 状態を先に見る（`drawn`・`closed` の満員のルームは「もう行き先が決まっています」と出す）。
 * @param room ルーム
 * @throws `room-already-decided`（`drawn`・`closed`）・`room-full`（メンバーが 20 人）
 */
export function assertJoinable(room: JoinableRoom): void {
  if (!JOINABLE_STATUSES.includes(room.status)) {
    throw appError("room-already-decided");
  }
  if (room.memberCount >= MAX_MEMBERS) {
    throw appError("room-full");
  }
}

/** 広告非表示の判定に使う、メンバーの情報 */
export interface SponsorCandidate {
  /** uid */
  uid: string;
  /** 表示名 */
  displayName: string;
  /** 広告非表示を購入済みか（`users.adFree`） */
  adFree: boolean;
}

/**
 * 参加した人を加えたあとの、広告非表示の購入者（05 の §3「購入者がいれば最初に参加した人」）。
 * すでに購入者がいれば、その人のほうが先に参加しているので変えない。
 * @param current いまの購入者
 * @param joiner 参加した人
 * @returns 新しい購入者（いなければ null）
 */
export function sponsorAfterJoin(current: AdFreeSponsor | null | undefined, joiner: SponsorCandidate): AdFreeSponsor | null {
  if (current !== null && current !== undefined) {
    return current;
  }
  return joiner.adFree ? { uid: joiner.uid, displayName: joiner.displayName } : null;
}

/**
 * メンバーが抜けたあとの、広告非表示の購入者。
 * 抜けた人が購入者だったときだけ、残りのメンバーから参加の早い順に購入者を探し直す。
 * @param current いまの購入者
 * @param removedUid 抜けた人の uid
 * @param remainingInJoinOrder 残りのメンバー（参加の早い順）
 * @returns 新しい購入者（いなければ null）
 */
export function sponsorAfterRemoval(
  current: AdFreeSponsor | null | undefined,
  removedUid: string,
  remainingInJoinOrder: readonly SponsorCandidate[],
): AdFreeSponsor | null {
  if (current !== null && current !== undefined && current.uid !== removedUid) {
    return current;
  }
  const next = remainingInJoinOrder.find((member) => member.adFree && member.uid !== removedUid);
  return next === undefined ? null : { uid: next.uid, displayName: next.displayName };
}

/** 退出・削除の判定に要るルームの値 */
export type OwnedRoom = Pick<RoomDoc, "ownerId">;

/**
 * 自分で退出できるか確かめる（02 の F-05「作成者は退出できない（MVP）」）。
 * @param room ルーム
 * @param uid 退出する人
 * @throws `owner-cannot-leave`
 */
export function assertCanLeave(room: OwnedRoom, uid: string): void {
  if (room.ownerId === uid) {
    throw appError("owner-cannot-leave");
  }
}

/**
 * メンバーを削除できるか確かめる（02 の F-05「作成者はメンバーを削除できる」）。
 * @param room ルーム
 * @param callerUid 呼んだ人
 * @param memberId 削除する人
 * @throws `not-room-owner`（作成者でない）・`cannot-remove-owner`（作成者を削除しようとした）
 */
export function assertCanRemove(room: OwnedRoom, callerUid: string, memberId: string): void {
  if (room.ownerId !== callerUid) {
    throw appError("not-room-owner");
  }
  if (memberId === room.ownerId) {
    throw appError("cannot-remove-owner");
  }
}

/** 日時のフィールドを、書き込むときの値（`FieldValue.serverTimestamp()` など）に置き換えた型 */
type WithTime<Doc, Keys extends keyof Doc, Time> = Omit<Doc, Keys> & { [Key in Keys]: Time };

/** 作るルームのドキュメント（日時は書き込むときの値） */
export type NewRoomDoc<Time, Deadline> = Omit<WithTime<RoomDoc, "createdAt", Time>, "settings"> & {
  settings: Omit<RoomDoc["settings"], "deadlineAt"> & { deadlineAt: Deadline | null };
};

/**
 * 作成直後のルーム（02 の F-02 の AC「作成直後のルームは open、メンバーは作成者1人」）。
 * @param input 検証した入力
 * @param owner 作成者
 * @param inviteCode 確保した招待コード
 * @param now 作成日時に書き込む値
 * @param deadline 締切日時を書き込む値に変える関数
 * @returns ルームのドキュメント
 */
export function newRoomDoc<Time, Deadline>(
  input: CreateRoomInput,
  owner: SponsorCandidate,
  inviteCode: string,
  now: Time,
  deadline: (ms: number) => Deadline,
): NewRoomDoc<Time, Deadline> {
  return {
    name: input.name,
    ownerId: owner.uid,
    inviteCode,
    status: "open",
    settings: {
      postLimit: input.postLimit,
      unlockRule: input.unlockRule,
      deadlineAt: input.deadlineAtMs === null ? null : deadline(input.deadlineAtMs),
      likeMode: input.likeMode,
    },
    forcedUnlock: false,
    memberIds: [owner.uid],
    memberCount: 1,
    readyCount: 0,
    candidateCount: 0,
    adFreeSponsor: sponsorAfterJoin(null, owner),
    currentDrawId: null,
    winnerCandidateId: null,
    excludedCandidateIds: [],
    reroll: initialRerollState(),
    createdAt: now,
    drawnAt: null,
    closedAt: null,
  };
}

/** 作るメンバーのドキュメント（日時は書き込むときの値） */
export type NewMemberDoc<Time> = WithTime<MemberDoc, "joinedAt" | "lastSeenAt", Time>;

/**
 * 参加したばかりのメンバー（02 の F-04「準備OKは false から始まる」）。
 * `lastSeenAt` は `joinedAt` と同じ値で作る（アプリのモデルが必須にしている。参加より前の候補を NEW にしない）。
 * @param member 参加する人
 * @param role 役割
 * @param now 参加日時に書き込む値
 * @returns メンバーのドキュメント
 */
export function newMemberDoc<Time>(
  member: Pick<SponsorCandidate, "displayName"> & { avatarColor: string },
  role: MemberRole,
  now: Time,
): NewMemberDoc<Time> {
  return {
    displayName: member.displayName,
    avatarColor: member.avatarColor,
    role,
    ready: false,
    joinedAt: now,
    lastSeenAt: now,
  };
}
