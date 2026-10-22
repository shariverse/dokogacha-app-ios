/**
 * 準備OKの数え直しと解禁（05 の §5 の `onMemberWrite`・`forceUnlock`・`checkDeadlines`）。
 * 何を書くかは `logic.ts` の `planUnlock`・`decideForceUnlock` が決め、ここでは Firestore を読み書きする。
 *
 * - ルームの `status`・`memberCount`・`readyCount` を、ルームとメンバーを読んだのと同じトランザクションで書く
 *   （準備OKと退出が同時に起きても、最後に確定したトランザクションが、その時点のメンバーから数え直した値を書く）
 * - `members` には書かない（`onMemberWrite` が自分の書き込みでもう一度動かないように）
 * - 解禁の通知（`notifyRoomUnlocked`）は、トランザクションが確定した後に、`open` から `unlocked` に変えたときだけ呼ぶ
 */
import { Timestamp, type DocumentReference, type Transaction } from "firebase-admin/firestore";

import { settleInGroups } from "../batch";
import type { RoomDoc, RoomStatus } from "../domain/models";
import type { UnlockReason } from "../domain/unlock";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { membersRef, roomRef } from "../paths";
import { parseRoomIdInput } from "./input";
import { countMembers, decideForceUnlock, planUnlock, type MemberCounts, type RoomUnlockState } from "./logic";
import { notifyRoomUnlocked } from "./notify";

/** 締切日時の判定で、同時に処理するルームの数（トランザクションを一度に開きすぎない） */
export const DEADLINE_CHECK_PARALLEL_ROOMS = 10;

/**
 * Firestore から読んだルームを、解禁の判定の値にする（締切日時をミリ秒にする。壊れた値は「無い」とみなす）。
 * @param room ルームのドキュメントの値
 */
export function unlockStateOf(room: Partial<RoomDoc>): RoomUnlockState {
  const deadlineAt = room.settings?.deadlineAt;
  return {
    status: room.status as RoomStatus,
    unlockRule: room.settings?.unlockRule,
    deadlineAtMs: deadlineAt instanceof Timestamp ? deadlineAt.toMillis() : null,
    forcedUnlock: room.forcedUnlock === true,
    rerollPassed: room.reroll?.status === "passed",
    memberCount: room.memberCount,
    readyCount: room.readyCount,
  };
}

/**
 * トランザクションの中で、ルームのメンバーを読んで数え直す（`members` をまるごと読む。最大 20 件）。
 * @param tx トランザクション
 * @param ref ルーム
 */
export async function readMemberCounts(tx: Transaction, ref: DocumentReference): Promise<MemberCounts> {
  const members = await tx.get(membersRef(ref));
  return countMembers(members.docs.map((doc) => doc.data() as { ready?: boolean }));
}

/** 数え直しの結果（テストとログで使う） */
export interface RecountResult {
  /** ルームに書いたか（数え直した値も状態も今と同じなら false） */
  changed: boolean;
  /** この数え直しで `open` から `unlocked` にしたときの理由（それ以外は null） */
  unlockedBy: UnlockReason | null;
}

/**
 * ルームのメンバーを数え直し、`memberCount`・`readyCount` と `open`⇄`unlocked` を書く（`onMemberWrite`・`checkDeadlines` の中身）。
 * 冪等（同じ状態で何度呼んでも、2 回目からは何も書かない）なので、トリガーのやり直し・重なりで呼ばれてもよい。
 * ルームが無い（削除された・テストで消した）ときは何もしない（`update` で作り直さない）。
 * @param deps 外部のもの（Firestore と今の時刻）
 * @param roomId ルームの ID
 * @returns 書いたかと、解禁したときの理由
 */
export async function recountRoom(deps: Pick<ServiceDeps, "db" | "nowMs">, roomId: string): Promise<RecountResult> {
  const ref = roomRef(deps.db, roomId);
  const plan = await deps.db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) {
      return null;
    }
    const counts = await readMemberCounts(tx, ref);
    const result = planUnlock(unlockStateOf(snapshot.data() as Partial<RoomDoc>), counts, deps.nowMs());
    if (Object.keys(result.update).length > 0) {
      tx.update(ref, { ...result.update });
    }
    return result;
  });
  if (plan === null) {
    return { changed: false, unlockedBy: null };
  }
  if (plan.unlockedBy !== null) {
    await notifyRoomUnlocked(roomId, plan.unlockedBy);
  }
  return { changed: Object.keys(plan.update).length > 0, unlockedBy: plan.unlockedBy };
}

/**
 * 作成者が強制解禁する（02 の F-32）。`open` のルームに `forcedUnlock = true`・`status = unlocked` を書く。
 * もう `unlocked` なら何も書かずに成功する（`decideForceUnlock`）。
 * @param deps 外部のもの
 * @param uid 呼んだ人（作成者であること）
 * @param data `request.data`（`{ roomId }`）
 */
export async function forceUnlock(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId } = parseRoomIdInput(data);
  const ref = roomRef(deps.db, roomId);
  const decision = await deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    const result = decideForceUnlock(room, uid);
    if (result === "unlock") {
      tx.update(ref, { forcedUnlock: true, status: "unlocked" });
    }
    return result;
  });
  if (decision === "unlock") {
    await notifyRoomUnlocked(roomId, "forced");
  }
  return {};
}

/** 締切日時の判定の結果（テストとログで使う） */
export interface DeadlineCheckResult {
  /** 締切を過ぎた `open` のルームの数（判定したルーム） */
  rooms: number;
  /** 解禁したルームの数 */
  unlocked: number;
}

/**
 * 締切日時を過ぎた `open` のルームを判定し直して `unlocked` にする（`checkDeadlines` の中身。5 分ごと）。
 *
 * クエリは `status == open` かつ `settings.deadlineAt <= 今`（`firestore.indexes.json` の複合インデックス）。
 * 条件が「締切日時」でないルームは `deadlineAt` が null なので入らない（入っても `judgeUnlock` が条件を見て解禁しない）。
 * 1 つのルームで失敗しても、残りのルームを最後まで処理してから投げる（次の実行でもう一度拾われる）。
 * @param deps 外部のもの（Firestore と今の時刻）
 * @returns 判定したルームの数と解禁した数
 */
export async function unlockPassedDeadlines(deps: Pick<ServiceDeps, "db" | "nowMs">): Promise<DeadlineCheckResult> {
  const now = Timestamp.fromMillis(deps.nowMs());
  const due = await deps.db
    .collection("rooms")
    .where("status", "==", "open")
    .where("settings.deadlineAt", "<=", now)
    .select()
    .get();
  const results = await settleInGroups(due.docs, DEADLINE_CHECK_PARALLEL_ROOMS, (doc) => recountRoom(deps, doc.id));
  return { rooms: due.size, unlocked: results.filter((result) => result.unlockedBy !== null).length };
}
