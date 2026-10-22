/**
 * プロフィールの表示名・アバターの色を、参加中のルームの複製に反映する（05 の §5 の `onUserProfileUpdate` の中身）。
 * 何を書くかは `logic.ts` の `planRoomCopyUpdates` が決め、ここでは Firestore を読み書きする。
 *
 * - ルームごとに 1 つのトランザクションで書く。1 つのルームで書くのは、メンバー 1 件・ルーム 1 件（購入者のとき）・
 *   自分の候補（投稿数の上限 `settings.postLimit` の 10 件まで）なので、トランザクションの書き込みの上限（500）を超えない。
 *   参加したルームの数には上限が無い（終了したルームも残る）ので、ルームの数だけトランザクションを分ける
 * - トランザクションの中でプロフィールを読み直し、その時点の値を書く。表示名を続けて変えてトリガーの順が前後しても、
 *   最後に動いたものが今の値を書くので、古い名前に戻らない
 * - 今の値と同じものは書かない（冪等。同じ更新でトリガーが 2 回動いても、2 回目は何も書かない）
 */
import type { Firestore, Transaction } from "firebase-admin/firestore";

import type { MemberDoc, RoomDoc, UserDoc } from "../domain/models";
import { candidatesRef, membersRef, roomRef, userRef } from "../paths";
import { chunk, countRoomCopyWrites, planRoomCopyUpdates } from "./logic";

/** 同時に処理するルームの数（ルームが多い人でも、トランザクションを一度に開きすぎない） */
export const PROFILE_SYNC_PARALLEL_ROOMS = 10;

/** 反映の結果（テストとログで使う） */
export interface ProfileSyncResult {
  /** 見たルームの数（`memberIds` に自分がいるルーム） */
  rooms: number;
  /** 書き込んだドキュメントの数（すでに今の値なら 0） */
  writes: number;
}

/**
 * 1 つのルームの複製を、トランザクションの中で今のプロフィールに合わせる。
 * @returns 書き込んだドキュメントの数
 */
async function syncRoom(db: Firestore, uid: string, roomId: string): Promise<number> {
  return db.runTransaction(async (tx: Transaction) => {
    const ref = roomRef(db, roomId);
    const profile = (await tx.get(userRef(db, uid))).data() as UserDoc | undefined;
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (profile === undefined || room === undefined) {
      return 0;
    }
    const memberRef = membersRef(ref).doc(uid);
    const member = (await tx.get(memberRef)).data() as MemberDoc | undefined;
    const posted = await tx.get(candidatesRef(ref).where("postedBy", "==", uid));
    const updates = planRoomCopyUpdates(uid, profile, {
      memberIds: room.memberIds,
      adFreeSponsor: room.adFreeSponsor ?? null,
      member,
      candidates: posted.docs.map((doc) => ({ id: doc.id, postedByName: String(doc.get("postedByName")) })),
    });

    if (updates.member !== null) {
      tx.update(memberRef, updates.member);
    }
    if (updates.sponsor !== null) {
      tx.update(ref, { adFreeSponsor: updates.sponsor });
    }
    for (const candidateId of updates.candidateIds) {
      tx.update(candidatesRef(ref).doc(candidateId), { postedByName: profile.displayName });
    }
    return countRoomCopyWrites(updates);
  });
}

/**
 * `uid` が参加しているすべてのルーム（`memberIds` に自分がいるルーム。状態は問わない）の複製を、今のプロフィールに合わせる。
 * @param db Firestore（Admin SDK）
 * @param uid プロフィールの持ち主
 * @returns 見たルームの数と書き込んだ数
 */
export async function syncProfileCopies(db: Firestore, uid: string): Promise<ProfileSyncResult> {
  // ルームの ID だけが要るので、フィールドを読まない（`select()`）
  const rooms = await db.collection("rooms").where("memberIds", "array-contains", uid).select().get();
  let writes = 0;
  for (const group of chunk(rooms.docs, PROFILE_SYNC_PARALLEL_ROOMS)) {
    const counts = await Promise.all(group.map((doc) => syncRoom(db, uid, doc.id)));
    writes += counts.reduce((sum, count) => sum + count, 0);
  }
  return { rooms: rooms.size, writes };
}
