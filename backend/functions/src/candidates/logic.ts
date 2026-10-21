/**
 * 候補の追加・削除の判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `service.ts` が行い、判定はここに切り出して Jest で確かめる。
 * 擬似のサーバー（`Dokogacha/Data/InMemory/InMemoryServer+Functions.swift`）も同じ順で判定する。
 */
import { findDuplicateCandidate, nextColorIndex, type ExistingCandidate } from "../domain/candidate";
import { MAX_CANDIDATES } from "../domain/constants";
import type { CandidateDoc, RoomDoc, RoomStatus } from "../domain/models";
import { appError } from "../errors";
import type { AddCandidateInput } from "./input";

/** 候補を追加・削除できる状態（02 の §2.1「open・unlocked：候補の投稿・削除」。drawn・closed は不可） */
export const CANDIDATE_EDITABLE_STATUSES: readonly RoomStatus[] = ["open", "unlocked"];

/**
 * 候補を追加・削除できる状態か確かめる。
 * @param room ルーム
 * @throws `room-already-decided`（`drawn`・`closed`）
 */
export function assertCandidatesEditable(room: Pick<RoomDoc, "status">): void {
  if (!CANDIDATE_EDITABLE_STATUSES.includes(room.status)) {
    throw appError("room-already-decided");
  }
}

/** `addCandidate` の判定の結果 */
export type AddCandidateDecision =
  /** 同じ場所がすでにある（作らずに、その候補の ID を返す） */
  | { kind: "duplicate"; candidateId: string }
  /** 追加してよい（新しい候補の `colorIndex`） */
  | { kind: "add"; colorIndex: number };

/**
 * 候補を追加してよいか判定する（02 の F-10）。呼んだ人がメンバーであることは、呼ぶ側で確かめておく。
 * 順に確かめる:
 * 1. 状態が `open`・`unlocked`（違えば `room-already-decided`）
 * 2. 同じ場所（`isSamePlace`）の候補がある → 作らずに `duplicate`（自分の投稿でも。上限に達していても重複を先に返す。
 *    アプリは「すでに候補にあります。いいねしますか？」を出し、上限のときも既存の候補にいいねできる）
 * 3. 自分の投稿数がルームの上限（`settings.postLimit`）に達している → `post-limit-reached`
 * 4. ルームの候補が 200 件に達している → `room-candidates-full`
 * 5. 追加する。`colorIndex` は既存の最大 + 1
 * @param room ルーム
 * @param uid 投稿する人
 * @param place 追加する場所
 * @param existing ルームの既存の候補（すべて）
 * @returns 判定の結果
 * @throws `room-already-decided`・`post-limit-reached`・`room-candidates-full`
 */
export function decideAddCandidate(
  room: Pick<RoomDoc, "status" | "settings">,
  uid: string,
  place: AddCandidateInput["place"],
  existing: readonly ExistingCandidate[],
): AddCandidateDecision {
  assertCandidatesEditable(room);
  const duplicate = findDuplicateCandidate(place, existing);
  if (duplicate !== null) {
    return { kind: "duplicate", candidateId: duplicate };
  }
  if (existing.filter((candidate) => candidate.postedBy === uid).length >= room.settings.postLimit) {
    throw appError("post-limit-reached");
  }
  if (existing.length >= MAX_CANDIDATES) {
    throw appError("room-candidates-full");
  }
  return { kind: "add", colorIndex: nextColorIndex(existing.map((candidate) => candidate.colorIndex)) };
}

/**
 * 候補を削除してよいか確かめる（02 の F-11「投稿者本人は open・unlocked のときに自分の候補を削除できる」
 * 「作成者は誰の候補でも削除できる」）。作成者の削除も `open`・`unlocked` のときだけにする
 * （`drawn` で消すと当選した候補・抽選の記録と合わなくなり、`closed` は閲覧のみ（02 の §2.1））。
 * @param room ルーム
 * @param uid 削除する人
 * @param candidate 削除する候補
 * @throws `not-candidate-owner`・`room-already-decided`
 */
export function assertCanDeleteCandidate(
  room: Pick<RoomDoc, "status" | "ownerId">,
  uid: string,
  candidate: Pick<CandidateDoc, "postedBy">,
): void {
  if (candidate.postedBy !== uid && room.ownerId !== uid) {
    throw appError("not-candidate-owner");
  }
  assertCandidatesEditable(room);
}

/** 作る候補のドキュメント（投稿日時は書き込むときの値） */
export type NewCandidateDoc<Time> = Omit<CandidateDoc, "createdAt" | "place" | "url" | "fromPastIdeaId"> & {
  place: AddCandidateInput["place"];
  url: string | null;
  fromPastIdeaId: string | null;
  createdAt: Time;
};

/**
 * 追加する候補（いいねは 0 から。投稿した人の表示名は、ルームの中の表示名（members のコピー）を写す）。
 * @param input 検証した入力
 * @param poster 投稿する人
 * @param colorIndex 採番した番号
 * @param now 投稿日時に書き込む値
 * @returns 候補のドキュメント
 */
export function newCandidateDoc<Time>(
  input: AddCandidateInput,
  poster: { uid: string; displayName: string },
  colorIndex: number,
  now: Time,
): NewCandidateDoc<Time> {
  return {
    place: input.place,
    category: input.category,
    note: input.note,
    url: input.url,
    postedBy: poster.uid,
    postedByName: poster.displayName,
    colorIndex,
    likedBy: [],
    fromPastIdeaId: input.fromPastIdeaId,
    createdAt: now,
  };
}
