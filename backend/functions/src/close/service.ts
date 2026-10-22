/**
 * ルームの終了（05 の §5 の `closeRoom`・`autoCloseRooms`）と、終了したときの過去のアイデアの登録（`onRoomClosed` の中身）。
 * 何をするかは `logic.ts` の `decideClose`・`isAutoCloseDue`・`planPastIdeas` が決め、ここでは Firestore を読み書きする。
 *
 * - 終了は、ルームを読んだのと同じトランザクションで `status = closed`・`closedAt`（サーバーの時刻）を書くだけ
 *   （作成者の決定と自動の終了が重なっても、後から確定する方は `closed` を読んで何もしない）
 * - 過去のアイデアは、`closed` になったことを受けたトリガーが `registerPastIdeas` で書く（2 つの道で同じ処理を使う）。
 *   最大 20 人 × 199 件になりうるので、終了のトランザクションには入れない（トランザクションを大きくしない）
 */
import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";

import { chunk, settleInGroups } from "../batch";
import type { RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { candidatesRef, roomRef, userRef } from "../paths";
import { parseRoomIdInput } from "../unlock/input";
import {
  autoCloseCutoffMs,
  decideClose,
  isAutoCloseDue,
  PAST_IDEA_BATCH_SIZE,
  planPastIdeas,
  rerollUpdateOnClose,
} from "./logic";

/** 自動の終了で、同時に処理するルームの数（トランザクションを一度に開きすぎない） */
export const AUTO_CLOSE_PARALLEL_ROOMS = 10;

/**
 * 終了のトランザクションで書く値（引き直しの投票中なら、同じ書き込みで否決にする。`rerollUpdateOnClose`）
 * @param room トランザクションで読んだルーム
 */
function closedUpdate(room: Partial<RoomDoc>): Record<string, unknown> {
  return { ...rerollUpdateOnClose(room), status: "closed", closedAt: FieldValue.serverTimestamp() };
}

/**
 * 作成者がルームを終了する（02 の §6.3「この行き先で決定」・F-44）。`drawn` のルームを `closed` にする。
 * もう `closed` なら何も書かずに成功する（`decideClose`）。過去のアイデアはトリガー（`onRoomClosed`）が登録する。
 * @param deps 外部のもの
 * @param uid 呼んだ人（作成者であること）
 * @param data `request.data`（`{ roomId }`）
 * @throws `invalid-argument`・`room-not-found`・`not-room-member`・`not-room-owner`・`room-not-drawn`
 */
export async function closeRoom(deps: Pick<ServiceDeps, "db">, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId } = parseRoomIdInput(data);
  const ref = roomRef(deps.db, roomId);
  await deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    if (decideClose(room, uid) === "close") {
      tx.update(ref, closedUpdate(room));
    }
  });
  return {};
}

/**
 * 抽選から 7 日たったルームを 1 つ終了する（`autoCloseRooms` の中身の 1 件分）。
 * トランザクションの中で読み直して確かめる（クエリの後に作成者が決定した・引き直しが可決して `unlocked` に戻ったルームは書かない）。
 * @param deps 外部のもの（今の時刻）
 * @param roomId ルームの ID
 * @returns 終了したか
 */
export async function autoCloseRoom(deps: Pick<ServiceDeps, "db" | "nowMs">, roomId: string): Promise<boolean> {
  const ref = roomRef(deps.db, roomId);
  return deps.db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as Partial<RoomDoc> | undefined;
    if (room === undefined) {
      return false;
    }
    const drawnAt = room.drawnAt;
    const due = isAutoCloseDue(
      { status: room.status, drawnAtMs: drawnAt instanceof Timestamp ? drawnAt.toMillis() : null },
      deps.nowMs(),
    );
    if (due) {
      tx.update(ref, closedUpdate(room));
    }
    return due;
  });
}

/** 自動の終了の結果（テストとログで使う） */
export interface AutoCloseResult {
  /** 抽選から 7 日たった `drawn` のルームの数（クエリで見つけた数） */
  rooms: number;
  /** 終了したルームの数 */
  closed: number;
}

/**
 * 抽選から 7 日たった `drawn` のルームを `closed` にする（`autoCloseRooms` の中身。1 日 1 回）。
 *
 * クエリは `status == drawn` かつ `drawnAt <= 今 − 7 日`（`firestore.indexes.json` の複合インデックス）。
 * 1 つのルームで失敗しても、残りのルームを最後まで処理してから投げる（次の実行でもう一度拾われる）。
 * @param deps 外部のもの（Firestore と今の時刻）
 * @returns 見つけたルームの数と終了した数
 */
export async function closeOverdueRooms(deps: Pick<ServiceDeps, "db" | "nowMs">): Promise<AutoCloseResult> {
  const cutoff = Timestamp.fromMillis(autoCloseCutoffMs(deps.nowMs()));
  const due = await deps.db
    .collection("rooms")
    .where("status", "==", "drawn")
    .where("drawnAt", "<=", cutoff)
    .select()
    .get();
  const results = await settleInGroups(due.docs, AUTO_CLOSE_PARALLEL_ROOMS, (doc) => autoCloseRoom(deps, doc.id));
  return { rooms: due.size, closed: results.filter((closed) => closed).length };
}

/**
 * 終了したルームの、当選しなかった候補を、終了したときの各メンバーの過去のアイデア（`users/{uid}/pastIdeas`）に登録する
 * （02 の §6.5・F-13。`onRoomClosed` の中身）。
 *
 * 宛先・ルーム名・当選・終了の日時は、トリガーが受け取った終了した時点のルームの値（`event.data.after`）を `closedRoom` で受け取って使う。
 * 読み直すと、終了の直後（トリガーが動く前・やり直しの前）に退出・削除された人が `memberIds` から外れていて、登録されないため。
 * `closedRoom` を渡さないとき（テスト・手で流し直すとき）は、ルームを読み直す。どちらも `closed` でなければ何もしない。
 *
 * 候補（場所・いいね数）はトリガーの時点で読む。`closed` ではいいねを書けない（ルール）ので、終了の後にいいねが増えることは無いが、
 * 終了の直後に退出・削除された人のいいねは `likedBy` から外れているので、その分だけ「前回 N いいね」が少なくなりうる
 * （終了のトランザクションに候補の写しを入れると、最大 199 件を書くことになるので入れない）。
 *
 * ID は元のルームと候補から決まり（`pastIdeaId`）、値もルームと候補から決まるので、何度呼んでも同じドキュメントに同じ値を書く
 * （冪等。トリガーのやり直しで重ねて作らない）。件数が多いときは `PAST_IDEA_BATCH_SIZE` 件ずつのバッチで書く。
 * @param db Firestore
 * @param roomId ルームの ID
 * @param closedRoom 終了した時点のルームの値（トリガーの `event.data.after`。無ければ読み直す）
 * @returns 書いた過去のアイデアの数（メンバー × 候補）
 */
export async function registerPastIdeas(db: Firestore, roomId: string, closedRoom?: Partial<RoomDoc>): Promise<number> {
  const ref = roomRef(db, roomId);
  const room = closedRoom ?? (await ref.get()).data();
  if (room?.status !== "closed") {
    return 0;
  }
  const candidates = await candidatesRef(ref).get();
  const writes = planPastIdeas(
    {
      roomId,
      name: typeof room.name === "string" ? room.name : "",
      winnerCandidateId: typeof room.winnerCandidateId === "string" ? room.winnerCandidateId : null,
      memberIds: Array.isArray(room.memberIds) ? room.memberIds : [],
      closedAt: room.closedAt instanceof Timestamp ? room.closedAt : Timestamp.now(),
    },
    candidates.docs.map((doc) => ({ id: doc.id, data: doc.data() })),
  );
  for (const group of chunk(writes, PAST_IDEA_BATCH_SIZE)) {
    const batch = db.batch();
    for (const write of group) {
      batch.set(userRef(db, write.uid).collection("pastIdeas").doc(write.ideaId), write.doc);
    }
    await batch.commit();
  }
  return writes.length;
}
