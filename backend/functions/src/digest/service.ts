/**
 * 新しい候補のまとめ通知（`notifyNewCandidates`。1 日 1 回 20:00 JST）。判定は `logic.ts`。
 *
 * 1. まとめる範囲（前の日の 20:00〜今日の 20:00 JST）に作られた候補を、すべてのルームから集める
 *    （`candidates` のコレクショングループを `createdAt` で絞る。`firestore.indexes.json` の `fieldOverrides`。
 *    ルームを全部読まずに、その日に候補が増えたルームだけを読む）
 * 2. そのルームを読み、送る出来事を決める（`planDigests`）
 * 3. ルームごとに送る。同じルームに同じ日は 1 回だけ（`notificationLog` の `newCandidates-{日}`。やり直しで 2 回届かない）
 *
 * 1 つのルームで失敗しても、残りのルームを送ってから投げる（スケジュールのやり直しで、送っていないルームだけが送られる）。
 */
import { Timestamp } from "firebase-admin/firestore";

import { chunk, settleInGroups } from "../batch";
import type { ServiceDeps } from "../deps";
import type { RoomDoc } from "../domain/models";
import { deliver, type NotificationDeps } from "../notifications/service";
import { roomRef } from "../paths";
import { digestWindow, planDigests, type DigestRoom, type NewCandidate } from "./logic";

/** 同時に送るルームの数 */
export const DIGEST_PARALLEL_ROOMS = 10;
/** ルームを一度に読む数（`getAll` に渡す数） */
const ROOM_READ_BATCH = 100;

/** まとめ通知の結果（ログ用） */
export interface DigestResult {
  /** まとめる日 */
  dateKey: string;
  /** 範囲に作られた候補の数 */
  candidates: number;
  /** 送ったルームの数（もう送ってあったルームを含まない） */
  sentRooms: number;
}

/**
 * その日のまとめ通知を送る（`notifyNewCandidates` の中身）。
 * @param deps 外部のもの（Firestore と今の時刻。`sender` を足すと送り方を差し替えられる）
 */
export async function sendNewCandidateDigests(
  deps: Pick<ServiceDeps, "db" | "nowMs"> & NotificationDeps,
): Promise<DigestResult> {
  const window = digestWindow(deps.nowMs());
  const snapshot = await deps.db
    .collectionGroup("candidates")
    .where("createdAt", ">=", Timestamp.fromMillis(window.startMs))
    .where("createdAt", "<", Timestamp.fromMillis(window.endMs))
    .select("postedBy")
    .get();
  const candidates: NewCandidate[] = snapshot.docs.flatMap((doc) => {
    const room = doc.ref.parent.parent;
    const postedBy = doc.get("postedBy") as unknown;
    return room === null || room.parent.id !== "rooms" || typeof postedBy !== "string" ? [] : [{ roomId: room.id, postedBy }];
  });
  const roomIds = [...new Set(candidates.map((candidate) => candidate.roomId))];
  const rooms = new Map<string, DigestRoom & Pick<RoomDoc, "memberIds">>();
  for (const ids of chunk(roomIds, ROOM_READ_BATCH)) {
    const docs = await deps.db.getAll(...ids.map((id) => roomRef(deps.db, id)));
    for (const doc of docs) {
      const room = doc.data() as Partial<RoomDoc> | undefined;
      if (typeof room?.name === "string" && typeof room.status === "string" && Array.isArray(room.memberIds)) {
        rooms.set(doc.id, { name: room.name, status: room.status, memberIds: room.memberIds });
      }
    }
  }
  const events = planDigests(candidates, rooms, window.dateKey);
  const outcomes = await settleInGroups(events, DIGEST_PARALLEL_ROOMS, (event) =>
    deliver(deps, { memberIds: rooms.get(event.roomId)?.memberIds ?? [] }, event),
  );
  return {
    dateKey: window.dateKey,
    candidates: candidates.length,
    sentRooms: outcomes.filter((outcome) => outcome.kind === "sent").length,
  };
}
