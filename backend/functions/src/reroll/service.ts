/**
 * 引き直し（05 の §5 の `proposeReroll`・`voteReroll`・`expireRerolls`）。
 * ルームを読んだのと同じトランザクションで、票と状態（可決なら `unlocked` と除外リスト）を書く
 * （同時に何人が投票しても、後から確定する方はやり直しで最新の票を読んでから数える）。
 * 何を書くかは `logic.ts` が決め、ここでは Firestore を読み書きする。
 */
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { settleInGroups } from "../batch";
import { REROLL_VOTING_DURATION_MS } from "../domain/constants";
import type { RerollState, RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { roomRef } from "../paths";
import { parseRoomIdInput } from "../unlock/input";
import { parseVoteRerollInput } from "./input";
import { planExpiry, planPropose, planVote, rerollUpdateOf, type RerollPlan } from "./logic";
import { notifyRerollProposed } from "./notify";

/** 期限の判定で、同時に処理するルームの数（トランザクションを一度に開きすぎない） */
export const REROLL_EXPIRY_PARALLEL_ROOMS = 10;

/**
 * 引き直しを提案する（02 の §6.4。`drawn` のときだけ・ルームにつき 1 回・提案者は自動で賛成）。
 * 提案者だけで過半数（1 人のルーム）ならその場で可決する。ほかの人が先に提案していたら、賛成の票として数える。
 * 通知の呼び出し口は、新しく提案したときだけ、トランザクションの後に呼ぶ。
 * @param deps 外部のもの
 * @param uid 提案する人
 * @param data `request.data`（`{ roomId }`）
 */
export async function proposeReroll(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId } = parseRoomIdInput(data);
  const ref = roomRef(deps.db, roomId);
  const decision = await deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    const result = planPropose(room, uid);
    const update = rerollUpdateOf(result.plan);
    if (result.kind === "propose") {
      update["reroll.used"] = true;
      update["reroll.proposedBy"] = uid;
      update["reroll.proposedAt"] = FieldValue.serverTimestamp();
    }
    tx.update(ref, update);
    return result.kind;
  });
  if (decision === "propose") {
    await notifyRerollProposed(deps, roomId, uid);
  }
  return {};
}

/**
 * 引き直しに投票する（賛成／反対。メンバーだけ・1 人 1 票・投票中は変えられる）。賛成が過半数になったら可決する。
 * @param deps 外部のもの
 * @param uid 投票する人
 * @param data `request.data`（`{ roomId, approve }`）
 */
export async function voteReroll(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId, approve } = parseVoteRerollInput(data);
  const ref = roomRef(deps.db, roomId);
  await deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    tx.update(ref, rerollUpdateOf(planVote(room, uid, approve)));
  });
  return {};
}

/** 期限の判定の結果（テストとログで使う） */
export interface RerollExpiryResult {
  /** 期限を過ぎた投票中のルームの数（判定したルーム） */
  rooms: number;
  /** 否決にしたルームの数 */
  rejected: number;
  /** 可決にしたルームの数（期限の時点で過半数だった） */
  passed: number;
}

/**
 * 1 つのルームの期限を、トランザクションで読み直してから判定する（クエリの後に投票・可決していれば何もしない）。
 * @param deps 外部のもの
 * @param roomId ルームの ID
 * @returns 書いた値（何もしなければ null）
 */
async function expireRoom(deps: Pick<ServiceDeps, "db" | "nowMs">, roomId: string): Promise<RerollPlan | null> {
  const ref = roomRef(deps.db, roomId);
  return deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      return null;
    }
    // 壊れたデータ（reroll が無い）でも止めない
    const reroll = room.reroll as Partial<RerollState> | undefined;
    const proposedAt = reroll?.proposedAt;
    const plan = planExpiry(room, proposedAt instanceof Timestamp ? proposedAt.toMillis() : null, deps.nowMs());
    if (plan !== null) {
      tx.update(ref, rerollUpdateOf(plan));
    }
    return plan;
  });
}

/**
 * 提案から 24 時間を過ぎた投票を否決にする（`expireRerolls` の中身。1 時間ごと。06 の §4 の仮決め）。
 *
 * クエリは `reroll.status == voting` かつ `reroll.proposedAt <= 今 - 24 時間`（`firestore.indexes.json` の複合インデックス）。
 * 1 つのルームで失敗しても、残りのルームを最後まで処理してから投げる（次の実行でもう一度拾われる）。
 * @param deps 外部のもの（Firestore と今の時刻）
 * @returns 判定したルームの数と、否決・可決にした数
 */
export async function expireRerolls(deps: Pick<ServiceDeps, "db" | "nowMs">): Promise<RerollExpiryResult> {
  const threshold = Timestamp.fromMillis(deps.nowMs() - REROLL_VOTING_DURATION_MS);
  const due = await deps.db
    .collection("rooms")
    .where("reroll.status", "==", "voting")
    .where("reroll.proposedAt", "<=", threshold)
    .select()
    .get();
  const plans = await settleInGroups(due.docs, REROLL_EXPIRY_PARALLEL_ROOMS, (doc) => expireRoom(deps, doc.id));
  return {
    rooms: due.size,
    rejected: plans.filter((plan) => plan?.status === "rejected").length,
    passed: plans.filter((plan) => plan?.status === "passed").length,
  };
}
