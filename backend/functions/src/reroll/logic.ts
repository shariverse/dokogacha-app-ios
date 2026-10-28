/**
 * 引き直し（02 の §6.4・F-43。05 の §5 の `proposeReroll`・`voteReroll`・`expireRerolls`）の判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `service.ts` が行い、判定と書く値はここに切り出して Jest で確かめる。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Reroll.swift`）も同じ順で判定する。
 *
 * 決まり:
 * - 提案できるのは `drawn` のときだけ・ルームにつき 1 回（`reroll.used`。否決の後も再提案できない）。提案者は自動で賛成
 * - 投票はメンバーだけ・1 人 1 票。投票中は賛成と反対を変えられる（変えると前の票は取り除く。同じ票をもう一度送っても何も変わらない）
 * - 賛成が過半数（`isRerollMajority`）になったら可決: 直前の当選を除外リストに足し、ルームを `unlocked` に戻す（準備OKはやり直さない）
 * - 提案から 24 時間（`REROLL_VOTING_DURATION_MS`）で過半数に届かなければ否決（`expireRerolls`）。
 *   投票を変えられるので、全員が投票しても期限までは否決にしない
 * - 投票中にメンバーが退出・削除されたら、残りのメンバーで判定し直す（賛成が過半数になれば、その場で可決）
 */
import { REROLL_VOTING_DURATION_MS } from "../domain/constants";
import type { RerollState, RoomDoc } from "../domain/models";
import { countApprovals, isRerollMajority } from "../domain/reroll";
import { appError } from "../errors";

/** 判定に使うルームの値（壊れたデータでも判定を止めないよう、配列は検証の前の値で受け取る） */
export type RerollRoom = Pick<RoomDoc, "status"> & {
  /** メンバーの uid（`memberIds`） */
  memberIds?: unknown;
  /** 当選した候補の ID */
  winnerCandidateId?: string | null;
  /** 引き直しで外れた候補の ID */
  excludedCandidateIds?: unknown;
  /** 引き直しの状態 */
  reroll?: Partial<RerollState> | null;
};

/** 投票を数え直した後に書く値 */
export interface RerollPlan {
  /** 賛成した人（今のメンバーだけ。重ねない） */
  votesFor: string[];
  /** 反対した人（今のメンバーだけ。重ねない） */
  votesAgainst: string[];
  /** 投票の状態（`passed` ならルームを `unlocked` に戻す。`rejected` は期限の後だけ） */
  status: "voting" | "passed" | "rejected";
  /** 可決したときの除外リスト（直前の当選を足したもの。可決でなければ null） */
  excludedCandidateIds: string[] | null;
}

/** `proposeReroll` の判定の結果 */
export type ProposeDecision =
  /** 新しく提案する（提案者は自動で賛成） */
  | { kind: "propose"; plan: RerollPlan }
  /** ほかの人がすでに提案していた（同時に押した）。提案の代わりに賛成の票として数える */
  | { kind: "approve"; plan: RerollPlan };

/**
 * 値を文字列の配列として読む（配列でない・文字列でない要素は捨てる）。
 * @param value Firestore から読んだ値
 */
function stringsOf(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

/**
 * 直前の当選を足した除外リスト（同じ候補を重ねない。当選が無い壊れたデータなら今のまま）。
 * @param room ルーム
 */
export function excludedAfterPass(room: Pick<RerollRoom, "winnerCandidateId" | "excludedCandidateIds">): string[] {
  const excluded = stringsOf(room.excludedCandidateIds);
  const winner = room.winnerCandidateId;
  if (typeof winner !== "string" || winner === "" || excluded.includes(winner)) {
    return excluded;
  }
  return [...excluded, winner];
}

/**
 * 票を数え直して、書く値を決める（今のメンバーの票だけを残し、賛成が過半数なら可決）。
 * @param room ルーム
 * @param memberIds 今のメンバーの uid
 * @param votesFor 賛成した人
 * @param votesAgainst 反対した人
 */
function planOf(room: RerollRoom, memberIds: readonly string[], votesFor: readonly string[], votesAgainst: readonly string[]): RerollPlan {
  const members = new Set(memberIds);
  const keep = (uids: readonly string[]) => [...new Set(uids.filter((uid) => members.has(uid)))];
  const approvals = keep(votesFor);
  const passed = isRerollMajority(countApprovals(approvals, memberIds), memberIds.length);
  return {
    votesFor: approvals,
    votesAgainst: keep(votesAgainst).filter((uid) => !approvals.includes(uid)),
    status: passed ? "passed" : "voting",
    excludedCandidateIds: passed ? excludedAfterPass(room) : null,
  };
}

/**
 * 1 人の票を入れ直す（前の票を取り除いてから、賛成か反対に入れる）。
 * @param room ルーム
 * @param voter 投票する人
 * @param approve 賛成なら true
 */
function planWithVote(room: RerollRoom, voter: string, approve: boolean): RerollPlan {
  const others = (uids: unknown) => stringsOf(uids).filter((uid) => uid !== voter);
  const votesFor = others(room.reroll?.votesFor);
  const votesAgainst = others(room.reroll?.votesAgainst);
  (approve ? votesFor : votesAgainst).push(voter);
  return planOf(room, stringsOf(room.memberIds), votesFor, votesAgainst);
}

/**
 * 呼んだ人がメンバーで、ルームが終了していないか確かめる（提案と投票で共通）。
 * @throws `not-room-member`・`room-closed`
 */
function assertOpenToMember(room: RerollRoom, uid: string): void {
  if (!stringsOf(room.memberIds).includes(uid)) {
    throw appError("not-room-member");
  }
  if (room.status === "closed") {
    throw appError("room-closed");
  }
}

/**
 * 引き直しを提案してよいか判定し、書く値を決める（02 の §6.4）。順に確かめる:
 * 1. メンバーか（`not-room-member`）・終了していないか（`room-closed`）
 * 2. `drawn` で投票中なら、ほかの人が先に提案していた（同時に押した）ので、賛成の票として数える（`approve`）
 * 3. 権利を使った後（投票中・可決・否決の後。`reroll.used`）なら `reroll-used`（F-43 の AC「2回目を提案できない」）
 * 4. `drawn` でない（`open`・`unlocked`）なら `room-not-drawn`
 * 5. 提案する（提案者は自動で賛成。1 人のルームならその場で可決）
 * @param room ルーム
 * @param uid 提案する人
 * @throws `not-room-member`・`room-closed`・`reroll-used`・`room-not-drawn`
 */
export function planPropose(room: RerollRoom, uid: string): ProposeDecision {
  assertOpenToMember(room, uid);
  const reroll = room.reroll;
  if (room.status === "drawn" && reroll?.status === "voting") {
    return { kind: "approve", plan: planWithVote(room, uid, true) };
  }
  if (reroll?.used === true || (reroll?.status !== undefined && reroll.status !== "none")) {
    throw appError("reroll-used");
  }
  if (room.status !== "drawn") {
    throw appError("room-not-drawn");
  }
  return { kind: "propose", plan: planOf(room, stringsOf(room.memberIds), [uid], []) };
}

/**
 * 引き直しに投票してよいか判定し、書く値を決める（02 の §6.4「賛成／反対」）。
 * @param room ルーム
 * @param uid 投票する人
 * @param approve 賛成なら true
 * @throws `not-room-member`・`room-closed`・`reroll-not-voting`（投票中でない・`drawn` でない）
 */
export function planVote(room: RerollRoom, uid: string, approve: boolean): RerollPlan {
  assertOpenToMember(room, uid);
  if (room.status !== "drawn" || room.reroll?.status !== "voting") {
    throw appError("reroll-not-voting");
  }
  return planWithVote(room, uid, approve);
}

/**
 * 投票の期限（提案から 24 時間）を過ぎたルームを判定する（`expireRerolls`。02 の §6.4「提案から24時間で過半数に届かなければ否決」）。
 * 期限を過ぎていて賛成が過半数でなければ否決にする（権利は使ったまま）。過半数なら可決にする
 * （投票のたびに判定するので通常は起きないが、取りこぼしても期限で必ず決着させる）。
 * @param room ルーム
 * @param proposedAtMs 提案した日時のミリ秒（無い壊れたデータなら null。期限を過ぎたものとして扱う）
 * @param nowMs 今の時刻のミリ秒
 * @returns 書く値（投票中でない・期限の前なら null）
 */
export function planExpiry(room: RerollRoom, proposedAtMs: number | null, nowMs: number): RerollPlan | null {
  if (room.reroll?.status !== "voting") {
    return null;
  }
  if (proposedAtMs !== null && nowMs - proposedAtMs < REROLL_VOTING_DURATION_MS) {
    return null;
  }
  const plan = planOf(room, stringsOf(room.memberIds), stringsOf(room.reroll.votesFor), stringsOf(room.reroll.votesAgainst));
  if (plan.status === "passed" && room.status === "drawn") {
    return plan;
  }
  return { ...plan, status: "rejected", excludedCandidateIds: null };
}

/**
 * メンバーが外れた（退出・削除）後に、投票中の引き直しを判定し直す（残りのメンバーで賛成が過半数なら可決）。
 * @param room 外れる前のルーム
 * @param leavingUid 外れる人
 * @returns 書く値（投票中でない・`drawn` でないなら null。可決しないときも、外れた人の票を除いた値を返す）
 */
export function planAfterLeave(room: RerollRoom, leavingUid: string): RerollPlan | null {
  if (room.status !== "drawn" || room.reroll?.status !== "voting") {
    return null;
  }
  const memberIds = stringsOf(room.memberIds).filter((uid) => uid !== leavingUid);
  return planOf(room, memberIds, stringsOf(room.reroll.votesFor), stringsOf(room.reroll.votesAgainst));
}

/**
 * 書く値を、ルームの更新（ネストしたフィールドはキーを文字列で持つ）にする。可決ならルームを `unlocked` に戻し、除外リストを書く。
 * 準備OK（`readyCount`・メンバーの `ready`）は変えない（02 の §6.4「準備OKはやり直さない」）。
 * @param plan 書く値
 */
export function rerollUpdateOf(plan: RerollPlan): Record<string, unknown> {
  const update: Record<string, unknown> = {
    "reroll.votesFor": plan.votesFor,
    "reroll.votesAgainst": plan.votesAgainst,
    "reroll.status": plan.status,
  };
  if (plan.status === "passed" && plan.excludedCandidateIds !== null) {
    update.status = "unlocked";
    update.excludedCandidateIds = plan.excludedCandidateIds;
  }
  return update;
}
