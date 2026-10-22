/**
 * 抽選（05 の §5 の `drawGacha`・`onRoomDrawn`）の判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `service.ts` が行い、判定はここに切り出して Jest で確かめる。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Draw.swift`）も同じ順で判定する。
 */
import type { MemberDoc, RoomDoc } from "../domain/models";
import { appError } from "../errors";
import { statusAfterRecount, type MemberCounts, type RoomUnlockState } from "../unlock/logic";

/** `drawGacha` の結果（アプリの `DrawGachaResponse` と同じ形） */
export interface DrawGachaResult {
  /** 抽選の ID（`draws/{drawId}`。先に誰かが回していれば、その抽選の ID） */
  drawId: string;
  /** 当選した候補の ID（回した人の画面が、購読を待たずにカプセルの色と結果を出せるように返す） */
  candidateId: string;
  /** 先に誰かが回していたか（true なら今回は抽選していない。02 の §6.1「2人目には既存の結果を返す」） */
  alreadyDrawn: boolean;
}

/** `drawGacha` の判定の結果 */
export type DrawDecision =
  /** 先に誰かが回していた（抽選せずに、その結果を返す） */
  | { kind: "alreadyDrawn"; drawId: string; candidateId: string }
  /** 抽選してよい（回した人の表示名は、ルームの中の表示名（members のコピー）を抽選の記録に写す） */
  | { kind: "draw"; drawnByName: string };

/** 判定に使うルームの値 */
export type DrawableRoom = Pick<RoomDoc, "status"> & Partial<Pick<RoomDoc, "currentDrawId" | "winnerCandidateId">>;

/**
 * ガチャを回してよいか判定する（02 の §6.1・05 の §5 の擬似コード）。順に確かめる:
 * 1. 呼んだ人がメンバー（`members/{uid}` がある。無ければ `not-room-member`）
 * 2. `drawn` で抽選の ID と当選がある → 抽選せずに、その結果を返す（同時に 2 人が回しても抽選は 1 回だけ）。
 *    `drawn` なのに抽選の ID が無い壊れたデータと `closed` は `room-already-decided`
 * 3. `unlocked` でない（`open`）→ `room-not-unlocked`
 * 4. `unlocked` でも、数え直した準備OKで判定し直すと `open` に戻る（参加の直後で `onMemberWrite` がまだ動いていない）→ `room-not-unlocked`。
 *    強制解禁・締切日時・引き直しの可決の後の扱いは `planUnlock` と同じ（`statusAfterRecount`）
 *
 * 候補が 0 件かどうかは、候補を読んでから `service.ts` が確かめる（`no-candidates`）。
 * @param room ルーム
 * @param member 呼んだ人のメンバーのドキュメント（無ければ undefined）
 * @param unlockState 解禁の判定に使うルームの値（`unlockStateOf`）
 * @param counts 数え直したメンバーの数
 * @param nowMs 今の時刻のミリ秒
 * @throws `not-room-member`・`room-already-decided`・`room-not-unlocked`
 */
export function decideDraw(
  room: DrawableRoom,
  member: Pick<MemberDoc, "displayName"> | undefined,
  unlockState: RoomUnlockState,
  counts: MemberCounts,
  nowMs: number,
): DrawDecision {
  if (member === undefined) {
    throw appError("not-room-member");
  }
  switch (room.status) {
    case "drawn": {
      const drawId = room.currentDrawId;
      const candidateId = room.winnerCandidateId;
      if (typeof drawId === "string" && drawId !== "" && typeof candidateId === "string" && candidateId !== "") {
        return { kind: "alreadyDrawn", drawId, candidateId };
      }
      throw appError("room-already-decided");
    }
    case "closed":
      throw appError("room-already-decided");
    case "open":
      throw appError("room-not-unlocked");
    case "unlocked":
      if (statusAfterRecount(unlockState, counts, nowMs) !== "unlocked") {
        throw appError("room-not-unlocked");
      }
      return { kind: "draw", drawnByName: member.displayName };
  }
}

/** 抽選の後の通知（`onRoomDrawn`）に渡す値 */
export interface DrawnEvent {
  /** 抽選の ID（`currentDrawId`） */
  drawId: string;
}

/**
 * ルームの更新が「抽選した」（`drawn` になった・引き直しの後にもう一度回して抽選の ID が変わった）か。
 * `onRoomDrawn` は、これが null でないときだけ通知の呼び出し口を呼ぶ。`drawn` のままほかのフィールド
 * （`memberCount` の数え直しなど）だけが変わった更新では null。
 * @param before 更新の前のルーム（無ければ undefined）
 * @param after 更新の後のルーム（無ければ undefined）
 */
export function drawnEventOf(
  before: Partial<Pick<RoomDoc, "status" | "currentDrawId">> | undefined,
  after: Partial<Pick<RoomDoc, "status" | "currentDrawId">> | undefined,
): DrawnEvent | null {
  const drawId = after?.currentDrawId;
  if (after?.status !== "drawn" || typeof drawId !== "string" || drawId === "") {
    return null;
  }
  if (before?.status === "drawn" && before.currentDrawId === drawId) {
    return null;
  }
  return { drawId };
}
