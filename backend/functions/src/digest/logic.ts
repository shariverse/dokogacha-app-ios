/**
 * 新しい候補のまとめ通知（02 の §8「新しい候補（まとめ）| 全メンバー |「{ルーム名}」に新しい候補が N件増えました
 * （同じルームにつき最大1日1回）」・05 の §5 の `notifyNewCandidates`・06 の §4 の仮決め「1日1回 20:00 JST」）の判定
 * （Firestore に触れない純粋な関数）。Firestore を読むのと送るのは `service.ts` が行う。
 *
 * - まとめる範囲は、前の日の 20:00 から今日の 20:00（JST）までの 24 時間に作られた候補（今残っているもの）。
 *   スケジュールが遅れて動いても・やり直しても、同じ範囲と同じ日（印のキー）になるよう、今の時刻から範囲を決める
 * - 送るのは候補を追加できるルーム（`open`・`unlocked`）だけ。行き先が決まった（`drawn`・`closed`）ルームの候補は知らせない
 * - N は範囲に作られた候補の数（ルームごと）。宛先は全メンバーで、増えた候補がすべて 1 人の投稿なら、その人には送らない
 *   （自分の投稿しか増えていない人に「新しい候補が増えました」と知らせない）
 */
import { NEW_CANDIDATES_DIGEST_TIME } from "../domain/constants";
import type { RoomDoc } from "../domain/models";
import type { PushEvent } from "../notifications/logic";

/** 1 時間のミリ秒 */
const HOUR_MS = 60 * 60 * 1000;
/** 1 日のミリ秒 */
const DAY_MS = 24 * HOUR_MS;
/** JST の UTC からのずれ（日本は夏時間が無いので固定） */
const JST_OFFSET_MS = 9 * HOUR_MS;

/** まとめ通知のスケジュール（`onSchedule` の `schedule`。タイムゾーンは `SCHEDULE_TIME_ZONE`） */
export function digestSchedule(): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `every day ${pad(NEW_CANDIDATES_DIGEST_TIME.hour)}:${pad(NEW_CANDIDATES_DIGEST_TIME.minute)}`;
}

/** まとめる範囲 */
export interface DigestWindow {
  /** まとめる日（JST の `YYYY-MM-DD`。範囲の終わりの日） */
  dateKey: string;
  /** 範囲の始まり（含む。UNIX 時刻のミリ秒） */
  startMs: number;
  /** 範囲の終わり（含まない。UNIX 時刻のミリ秒。今の時刻以前でいちばん新しい 20:00 JST） */
  endMs: number;
}

/**
 * 今の時刻から、まとめる範囲を決める（終わりは今の時刻以前でいちばん新しい 20:00 JST、始まりはその 24 時間前）。
 * @param nowMs 今の時刻（UNIX 時刻のミリ秒）
 */
export function digestWindow(nowMs: number): DigestWindow {
  const digestOffsetMs = NEW_CANDIDATES_DIGEST_TIME.hour * HOUR_MS + NEW_CANDIDATES_DIGEST_TIME.minute * 60 * 1000;
  // JST の 0:00 を起点にした時刻にして、日の単位で切り捨てる
  const jstMs = nowMs + JST_OFFSET_MS;
  let endJstMs = Math.floor(jstMs / DAY_MS) * DAY_MS + digestOffsetMs;
  if (endJstMs > jstMs) {
    endJstMs -= DAY_MS;
  }
  const endMs = endJstMs - JST_OFFSET_MS;
  return { dateKey: new Date(endJstMs).toISOString().slice(0, 10), startMs: endMs - DAY_MS, endMs };
}

/** 範囲に作られた候補 1 件（親のルームと投稿した人） */
export interface NewCandidate {
  /** 候補のルームの ID */
  roomId: string;
  /** 投稿した人の uid */
  postedBy: string;
}

/** まとめ通知を送るか決めるのに使うルーム */
export type DigestRoom = Pick<RoomDoc, "name" | "status">;

/**
 * ルームごとのまとめ通知を決める（送るルームの選び方・N・送らない人）。
 * @param candidates 範囲に作られた候補
 * @param rooms 候補のルーム（ルームの ID → ルーム。無いルームの候補は数えない）
 * @param dateKey まとめる日
 * @returns 送る出来事（ルームの ID の順）
 */
export function planDigests(
  candidates: readonly NewCandidate[],
  rooms: ReadonlyMap<string, DigestRoom>,
  dateKey: string,
): Extract<PushEvent, { kind: "newCandidates" }>[] {
  const postersByRoom = new Map<string, string[]>();
  for (const candidate of candidates) {
    postersByRoom.set(candidate.roomId, [...(postersByRoom.get(candidate.roomId) ?? []), candidate.postedBy]);
  }
  return [...postersByRoom.keys()].sort().flatMap((roomId) => {
    const room = rooms.get(roomId);
    const posters = postersByRoom.get(roomId) ?? [];
    if (room === undefined || (room.status !== "open" && room.status !== "unlocked") || posters.length === 0) {
      return [];
    }
    const distinct = new Set(posters);
    const onlyPosterId = distinct.size === 1 ? (posters[0] ?? null) : null;
    return [{ kind: "newCandidates" as const, roomId, roomName: room.name, dateKey, count: posters.length, onlyPosterId }];
  });
}
