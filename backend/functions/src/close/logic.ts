/**
 * ルームの終了（02 の §6.5 F-44・05 の §5 の `closeRoom`・`autoCloseRooms`）と、終了したときの過去のアイデア（F-13）の判定
 * （Firestore に触れない純粋な関数）。Firestore の読み書きは `service.ts` が行う。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Close.swift`）も同じ順で判定する。
 *
 * 終了は 2 つの道（作成者の「この行き先で決定」・抽選から 7 日）があり、どちらもルームを `closed` にするだけにする。
 * 過去のアイデアの登録は、`closed` になったことを受けた Firestore のトリガー（`onRoomClosed`）がまとめて行う
 * （同じ処理を両方から使う。登録は冪等なので、トリガーのやり直しで重ねて作らない）。
 */
import type { Timestamp } from "firebase-admin/firestore";

import { FALLBACK_PLACE_CATEGORY, isPlaceCategory } from "../domain/category";
import { AUTO_CLOSE_AFTER_DRAW_MS } from "../domain/constants";
import type { CandidateDoc, PastIdeaDoc, Place, RoomDoc } from "../domain/models";
import { appError } from "../errors";

/**
 * 抽選から 7 日たったルームを終了するスケジュール（05 の §5「1日1回」）。
 * 人が使っていない深夜の 4:00（JST）に動かす。1 日 1 回なので、終了するのは抽選から 7 日〜8 日の間になる
 */
export const AUTO_CLOSE_SCHEDULE = "every day 04:00";

/** 過去のアイデアを書くバッチ 1 つの最大の件数（Firestore のバッチの上限 500 より少なくする） */
export const PAST_IDEA_BATCH_SIZE = 400;

/** `closeRoom` の判定の結果。`close` = 終了する・`alreadyClosed` = もう終了している（何も書かない） */
export type CloseDecision = "close" | "alreadyClosed";

/** 判定に使うルームの値 */
export type ClosableRoom = Pick<RoomDoc, "status" | "ownerId"> & Partial<Pick<RoomDoc, "memberIds">>;

/**
 * 作成者が「この行き先で決定」でルームを終了できるか確かめる（02 の §6.3・§6.5）。順に確かめる:
 * 1. 呼んだ人がメンバー（`memberIds` にいる。いなければ `not-room-member`）
 * 2. 呼んだ人が作成者（違えば `not-room-owner`。02 の §6.3「作成者のみ」）
 * 3. 状態が `drawn`（`open`・`unlocked` は `room-not-drawn`。引き直しが可決して `unlocked` に戻ったルームも決定できない）
 *
 * もう `closed` なら失敗にせず、何もしない（`alreadyClosed`）。作成者が確認のダイアログを出している間に、
 * 抽選から 7 日たって自動で終了したとき・二度押しで、トーストを出さずにホームへ戻せるようにする。
 * 引き直しの投票中（`reroll.status` が `voting`）でも終了できる（作成者が行き先を決める。投票は終了とともに意味を失う）。
 * @param room ルーム
 * @param uid 呼んだ人
 * @throws `not-room-member`・`not-room-owner`・`room-not-drawn`
 */
export function decideClose(room: ClosableRoom, uid: string): CloseDecision {
  if (!Array.isArray(room.memberIds) || !room.memberIds.includes(uid)) {
    throw appError("not-room-member");
  }
  if (room.ownerId !== uid) {
    throw appError("not-room-owner");
  }
  switch (room.status) {
    case "drawn":
      return "close";
    case "closed":
      return "alreadyClosed";
    case "open":
    case "unlocked":
      throw appError("room-not-drawn");
  }
}

/**
 * 抽選から自動で終了するまでの時間（06 の §4 の仮決め 7 日）が過ぎたか（02 の §6.5「抽選から7日経過で自動的に closed」）。
 * ちょうど 7 日の時刻は「過ぎた」に入れる（締切日時と同じく、その時刻を含む）。
 * @param room ルームの状態と抽選の日時のミリ秒（無ければ null）
 * @param nowMs 今の時刻のミリ秒
 * @returns `drawn` で、抽選から 7 日以上たっていれば true
 */
export function isAutoCloseDue(room: { status: unknown; drawnAtMs: number | null }, nowMs: number): boolean {
  return room.status === "drawn" && room.drawnAtMs !== null && nowMs - room.drawnAtMs >= AUTO_CLOSE_AFTER_DRAW_MS;
}

/**
 * 自動で終了するルームを探すクエリの境目（`drawnAt` がこの時刻以前の `drawn`）。
 * @param nowMs 今の時刻のミリ秒
 * @returns 境目の時刻のミリ秒（`isAutoCloseDue` が true になる最も遅い抽選の日時）
 */
export function autoCloseCutoffMs(nowMs: number): number {
  return nowMs - AUTO_CLOSE_AFTER_DRAW_MS;
}

/**
 * ルームの更新が「終了した」（`closed` でなかったのが `closed` になった）か。
 * `onRoomClosed` は、これが true のときだけ過去のアイデアを登録する（`closed` のままの更新では何もしない）。
 * @param before 更新の前のルーム（無ければ undefined）
 * @param after 更新の後のルーム（無ければ undefined）
 */
export function roomClosedBy(
  before: Partial<Pick<RoomDoc, "status">> | undefined,
  after: Partial<Pick<RoomDoc, "status">> | undefined,
): boolean {
  return after?.status === "closed" && before?.status !== "closed";
}

/**
 * 過去のアイデアのドキュメントの ID（`users/{uid}/pastIdeas/{ideaId}`）。
 * 元のルームと候補から決まる値にして、登録をやり直しても同じドキュメントに同じ値を書く（重ねて作らない）
 * @param roomId 元のルームの ID
 * @param candidateId 元の候補の ID
 */
export function pastIdeaId(roomId: string, candidateId: string): string {
  return `${roomId}_${candidateId}`;
}

/** 登録する過去のアイデア 1 件（誰の・どの ID に・何を書くか） */
export interface PastIdeaWrite {
  /** 登録するメンバーの uid */
  uid: string;
  /** ドキュメントの ID（`pastIdeaId`） */
  ideaId: string;
  /** ドキュメントの値 */
  doc: PastIdeaDoc;
}

/** 過去のアイデアを決めるのに使う、終了したルームの値 */
export interface ClosedRoomSource {
  /** ルームの ID */
  roomId: string;
  /** ルーム名 */
  name: string;
  /** 当選した候補の ID（無ければ null） */
  winnerCandidateId: string | null;
  /** 終了したときのメンバーの uid */
  memberIds: readonly string[];
  /** 終了の日時（並び替え用。`sourceClosedAt`） */
  closedAt: Timestamp;
}

/**
 * 候補のドキュメントの場所を、過去のアイデアに写す形にする（形が壊れていれば null）
 * @param place 候補の `place`
 */
function placeOf(place: unknown): Place | null {
  if (typeof place !== "object" || place === null) {
    return null;
  }
  const value = place as Partial<Place>;
  if (typeof value.name !== "string" || typeof value.latitude !== "number" || typeof value.longitude !== "number") {
    return null;
  }
  return {
    name: value.name,
    area: typeof value.area === "string" ? value.area : "",
    latitude: value.latitude,
    longitude: value.longitude,
    mapItemId: typeof value.mapItemId === "string" ? value.mapItemId : null,
  };
}

/**
 * 終了したルームの、当選しなかった候補を、終了したときの各メンバーの過去のアイデアにする（02 の §6.5・§3.4 F-13）。
 *
 * - 対象は当選した候補（`winnerCandidateId`）以外のすべて。引き直しで除外された前の当選も入れる（02 の §3.4）。
 *   自分以外の投稿も入れる（02 の §3.4「自分以外の投稿も含む」）
 * - 宛先は終了したときのメンバー（`memberIds`）。前に退出した人には登録しない（もう参加していない）
 * - いいね数（`prevLikeCount`）は `likedBy` の数（`drawn` 以降はいいねを変えられないので、抽選の時点の数）
 * - 場所の形が壊れた候補は飛ばす。カテゴリが知らない値なら `town`（02 の §3.1 の既定）
 * - 並び順は「メンバー → 候補の ID」の順（結果を決まった順にしてテストで比べる）
 * @param room 終了したルーム
 * @param candidates ルームの候補（ID と値）
 * @returns 書く過去のアイデアの一覧
 */
export function planPastIdeas(
  room: ClosedRoomSource,
  candidates: readonly { id: string; data: Partial<CandidateDoc> }[],
): PastIdeaWrite[] {
  const winner = candidates.find((candidate) => candidate.id === room.winnerCandidateId);
  const winnerName = placeOf(winner?.data.place)?.name ?? "";
  const ideas = [...candidates]
    .filter((candidate) => candidate.id !== room.winnerCandidateId)
    .sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0))
    .flatMap((candidate) => {
      const place = placeOf(candidate.data.place);
      if (place === null) {
        return [];
      }
      const likedBy = candidate.data.likedBy;
      const doc: PastIdeaDoc = {
        sourceRoomId: room.roomId,
        sourceRoomName: room.name,
        sourceClosedAt: room.closedAt,
        sourceWinnerName: winnerName,
        place,
        category: isPlaceCategory(candidate.data.category) ? candidate.data.category : FALLBACK_PLACE_CATEGORY,
        prevLikeCount: Array.isArray(likedBy) ? likedBy.length : 0,
      };
      return [{ ideaId: pastIdeaId(room.roomId, candidate.id), doc }];
    });
  const members = [...new Set(room.memberIds)];
  return members.flatMap((uid) => ideas.map((idea) => ({ uid, ...idea })));
}
