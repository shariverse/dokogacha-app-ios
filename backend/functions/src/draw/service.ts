/**
 * 抽選（05 の §5 の `drawGacha`）。ルーム・メンバー・候補を 1 つのトランザクションで読み、抽選の記録を作ってルームを `drawn` にする。
 * 同時に 2 人が回しても、後から確定する方はトランザクションのやり直しで `drawn` を読み、同じ抽選の ID を返す（抽選は 1 回だけ）。
 * 判定は `logic.ts`、重み付きの選択は `domain/draw.ts`（乱数は `deps.random`。本番は `crypto.randomInt`）。
 */
import { FieldValue } from "firebase-admin/firestore";

import { drawCandidate } from "../domain/draw";
import { isOneOf, LIKE_MODES, type CandidateDoc, type DrawDoc, type MemberDoc, type RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { candidatesRef, drawsRef, membersRef, roomRef } from "../paths";
import { parseRoomIdInput } from "../unlock/input";
import { countMembers } from "../unlock/logic";
import { unlockStateOf } from "../unlock/service";
import { decideDraw, type DrawGachaResult } from "./logic";

/** 抽選の記録に書く値（日時はサーバーの時刻を書き込むときの値） */
type NewDrawDoc = Omit<DrawDoc, "createdAt"> & { createdAt: FieldValue };

/**
 * ガチャを回す（02 の F-40）。
 *
 * 1. 入力（`{ roomId }`）を検証する
 * 2. トランザクションでルーム・メンバー（すべて）・候補（すべて。最大 200 件）を読む
 * 3. メンバーか・状態・数え直した解禁を確かめる（`decideDraw`）。先に誰かが回していれば、その結果を返す
 * 4. 引き直しで除外した候補を外し、候補の ID 順に重みを並べて選ぶ（`drawCandidate`）。候補が 0 件なら `no-candidates`
 * 5. `draws/{drawId}` を作り、ルームを `drawn` にして `currentDrawId`・`winnerCandidateId`・`drawnAt` を書く
 *
 * 回した人の表示名（`drawnByName`）はルームの中の表示名（members のコピー）を写す。日時はどちらもサーバーの時刻。
 * 通知はトランザクションの後に `onRoomDrawn`（トリガー）が呼ぶ。
 * @param deps 外部のもの（乱数で当選を選ぶ）
 * @param uid 回した人
 * @param data `request.data`（`{ roomId }`）
 * @returns 抽選の ID と当選した候補の ID
 */
export async function drawGacha(deps: ServiceDeps, uid: string, data: unknown): Promise<DrawGachaResult> {
  const { roomId } = parseRoomIdInput(data);
  const { db } = deps;
  const ref = roomRef(db, roomId);
  return db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      throw appError("room-not-found");
    }
    const members = await tx.get(membersRef(ref));
    const member = members.docs.find((doc) => doc.id === uid)?.data() as MemberDoc | undefined;
    const counts = countMembers(members.docs.map((doc) => doc.data() as Partial<MemberDoc>));
    const decision = decideDraw(room, member, unlockStateOf(room), counts, deps.nowMs());
    if (decision.kind === "alreadyDrawn") {
      return { drawId: decision.drawId, candidateId: decision.candidateId, alreadyDrawn: true };
    }

    const candidates = await tx.get(candidatesRef(ref));
    const inputs = candidates.docs.map((doc) => {
      const likedBy = (doc.data() as Partial<CandidateDoc>).likedBy;
      return { id: doc.id, likeCount: Array.isArray(likedBy) ? likedBy.length : 0 };
    });
    const mode = isOneOf(LIKE_MODES, room.settings.likeMode) ? room.settings.likeMode : "boost";
    const excluded = Array.isArray(room.excludedCandidateIds) ? room.excludedCandidateIds : [];
    const result = drawCandidate(inputs, mode, excluded, deps.random);
    if (result === null) {
      throw appError("no-candidates");
    }

    const draw = drawsRef(ref).doc();
    const now = FieldValue.serverTimestamp();
    const record: NewDrawDoc = {
      candidateId: result.candidateId,
      probability: result.probability,
      weights: result.weights,
      drawnBy: uid,
      drawnByName: decision.drawnByName,
      isReroll: excluded.length > 0,
      createdAt: now,
    };
    tx.create(draw, record);
    tx.update(ref, { status: "drawn", currentDrawId: draw.id, winnerCandidateId: result.candidateId, drawnAt: now });
    return { drawId: draw.id, candidateId: result.candidateId, alreadyDrawn: false };
  });
}
