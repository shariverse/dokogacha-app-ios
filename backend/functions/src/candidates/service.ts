/**
 * 候補の追加・削除（05 の §5 の `addCandidate`・`deleteCandidate`）。
 * 上限・重複・状態の確認と書き込みを、1 つのトランザクションで行う（同時に追加しても上限を超えない・同じ場所が 2 件にならない）。
 * 判定は `logic.ts`、入力の検証は `input.ts` に切り出してある。
 */
import { FieldValue, Timestamp, type DocumentReference, type Transaction } from "firebase-admin/firestore";

import type { ExistingCandidate } from "../domain/candidate";
import type { CandidateDoc, MemberDoc, RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { candidatesRef, drawsRef, membersRef, roomRef, userRef } from "../paths";
import { parseAddCandidateInput, parseDeleteCandidateInput } from "./input";
import { assertCanDeleteCandidate, decideAddCandidate, isDrawnCandidate, newCandidateDoc } from "./logic";

/**
 * トランザクションの中で、ルームと呼んだ人のメンバーのドキュメントを読む。
 * ルームが無ければ `room-not-found`、メンバーでなければ `not-room-member`。
 * 投稿の報告（`reports/service.ts`）も同じ確かめ方をするので export する。
 */
export async function getRoomAsMember(
  tx: Transaction,
  ref: DocumentReference,
  uid: string,
): Promise<{ room: RoomDoc; member: MemberDoc }> {
  const room = (await tx.get(ref)).data() as RoomDoc | undefined;
  if (room === undefined) {
    throw appError("room-not-found");
  }
  const member = (await tx.get(membersRef(ref).doc(uid))).data() as MemberDoc | undefined;
  if (member === undefined) {
    throw appError("not-room-member");
  }
  return { room, member };
}

/**
 * 投稿日時をミリ秒にする（重複が複数あるときに古い順を決めるため）。
 * `serverTimestamp()` の書き込みは、確定してから読まれるので `Timestamp` になっている。それ以外の値は 0 とみなす。
 */
function createdAtMs(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : 0;
}

/** `addCandidate` の結果（05 の §5。追加したら `candidateId`、同じ場所があれば作らずに `duplicateOf`） */
export type AddCandidateResult = { candidateId: string } | { duplicateOf: string };

/**
 * 過去のアイデアから持ち込むとき（`fromPastIdeaId` があるとき）、それが呼んだ人の過去のアイデアにあるか、トランザクションの中で確かめる。
 * 無ければ（他人の・作り話の ID）`invalid-argument`。アプリは自分の過去のアイデアの一覧から選んだ ID だけを送るので、通常は出ない。
 * 過去のアイデアは本人しか読めず、消えるのはアカウントの削除のときだけ（02 の F-06）。
 * @throws `invalid-argument`
 */
async function assertOwnPastIdea(tx: Transaction, deps: ServiceDeps, uid: string, pastIdeaId: string | null): Promise<void> {
  if (pastIdeaId === null) {
    return;
  }
  const idea = await tx.get(userRef(deps.db, uid).collection("pastIdeas").doc(pastIdeaId));
  if (!idea.exists) {
    throw appError("invalid-argument");
  }
}

/**
 * 候補を追加する（02 の F-10。過去のアイデアからの持ち込み（F-13）も同じ判定で追加する）。
 * ルームの候補をすべて（最大 200 件）トランザクションの中で読み、状態・重複・上限を確かめてから作る。
 * 同じ場所があれば作らずに `{ duplicateOf }` を返す（アプリは「すでに候補にあります。いいねしますか？」を出す）。
 * 持ち込みのときは、持ち込み元が自分の過去のアイデアにあることも確かめ、`fromPastIdeaId` に残す
 * （いいねは 0 から・投稿者は自分。02 の §3.4。過去のアイデアは消さずに残す）。
 * @param deps 外部のもの
 * @param uid 投稿する人
 * @param data `request.data`（`{ roomId, place, category, note, url?, fromPastIdeaId? }`）
 * @returns 追加した候補の ID か、重複した既存の候補の ID
 */
export async function addCandidate(deps: ServiceDeps, uid: string, data: unknown): Promise<AddCandidateResult> {
  const input = parseAddCandidateInput(data);
  const { db } = deps;
  const ref = roomRef(db, input.roomId);
  return db.runTransaction(async (tx) => {
    const { room, member } = await getRoomAsMember(tx, ref, uid);
    await assertOwnPastIdea(tx, deps, uid, input.fromPastIdeaId);
    const snapshot = await tx.get(candidatesRef(ref));
    const existing = snapshot.docs.map((doc): ExistingCandidate => {
      const candidate = doc.data() as CandidateDoc;
      return {
        id: doc.id,
        place: candidate.place,
        postedBy: candidate.postedBy,
        colorIndex: candidate.colorIndex,
        createdAtMs: createdAtMs(candidate.createdAt),
      };
    });

    const decision = decideAddCandidate(room, uid, input.place, existing);
    if (decision.kind === "duplicate") {
      return { duplicateOf: decision.candidateId };
    }
    const candidate = candidatesRef(ref).doc();
    const poster = { uid, displayName: member.displayName };
    tx.create(candidate, newCandidateDoc(input, poster, decision.colorIndex, FieldValue.serverTimestamp()));
    tx.update(ref, { candidateCount: FieldValue.increment(1) });
    return { candidateId: candidate.id };
  });
}

/**
 * 候補を削除する（02 の F-11。投稿した人か作成者だけ・`open`・`unlocked` のときだけ・ガチャで当選した候補は消せない）。
 * いいね（`likedBy`）は候補のドキュメントの中にあるので、候補と一緒に消える。
 * 報告（`reports`。F-14・タスク 40）は運営が確かめるための記録なので、候補を消しても残す。
 * @param deps 外部のもの
 * @param uid 削除する人
 * @param data `request.data`（`{ roomId, candidateId }`）
 */
export async function deleteCandidate(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId, candidateId } = parseDeleteCandidateInput(data);
  const { db } = deps;
  const ref = roomRef(db, roomId);
  await db.runTransaction(async (tx) => {
    const { room } = await getRoomAsMember(tx, ref, uid);
    const candidateRef = candidatesRef(ref).doc(candidateId);
    const candidate = (await tx.get(candidateRef)).data() as CandidateDoc | undefined;
    if (candidate === undefined) {
      throw appError("candidate-not-found");
    }
    // 抽選の記録がこの候補を指しているか（ルームのフィールドから外れた古い当選も拾う。単一フィールドのインデックスで引ける）
    const draws = await tx.get(drawsRef(ref).where("candidateId", "==", candidateId).limit(1));
    assertCanDeleteCandidate(room, uid, candidate, isDrawnCandidate(room, candidateId, !draws.empty));
    tx.delete(candidateRef);
    tx.update(ref, { candidateCount: FieldValue.increment(-1) });
  });
  return {};
}
