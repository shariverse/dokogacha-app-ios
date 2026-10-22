/**
 * アカウントの削除（02 の §2.6 F-06・05 の §5 の `deleteAccount`）。
 * 何をするかは `logic.ts` の `accountDeletionActionOf` が決め、ここでは Firestore と Auth を読み書きする。
 *
 * 次の順に行う。どの段で失敗しても、もう一度呼べば続きから終わる（冪等）:
 * 1. 参加中のルーム（`memberIds` に自分がいるルーム。状態は問わない）から外す。ルームごとに 1 つのトランザクションで、
 *    退出と同じ処理（`removeFromRoom`。いいねの取り消し・広告の購入者の付け替え・引き直しの投票の判定し直し）を行う。
 *    作成者で終了していないルームは、同じ書き込みで終了（`closed`）する（過去のアイデアは `onRoomClosed` が残るメンバーに登録する）。
 *    外し終えたルームは `memberIds` から消えるので、やり直しのクエリには出てこない
 * 2. `users/{uid}`（表示名・アバターの色・通知のトークン・広告非表示の購入）を消す
 * 3. `users/{uid}/pastIdeas` を消す。2 の後に消すので、終了の直後に動いた過去のアイデアの登録が 1 と 3 の間に書いても残らない
 *    （登録は `users/{uid}` があるかをトランザクションで確かめてから書く。`close/service.ts` の `registerPastIdeas`）
 * 4. Auth のユーザーを消す（Admin SDK）。最後に消すので、途中で失敗しても、アプリは同じユーザーのままもう一度呼べる
 *
 * 1 のどれかのルームで失敗したら、残りのルームを処理してから投げ、2 から先に進まない（ユーザーのデータを残してやり直せるようにする）。
 * 候補（`postedBy`・`postedByName`）・抽選の記録（`drawnBy`・`drawnByName`）・投稿の報告・作成者のルームの `ownerId` は残す
 * （02 の F-06「投稿済みの候補は『退出したメンバー』の投稿として残す」。プライバシーポリシーの「6. 保存する期間と削除」）。
 */
import type { DocumentReference, Firestore } from "firebase-admin/firestore";

import { chunk, settleInGroups } from "../batch";
import { closedUpdate } from "../close/service";
import type { RoomDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { roomRef, userRef } from "../paths";
import { removeFromRoom } from "../rooms/service";
import { accountDeletionActionOf, isAuthUserNotFound, type AccountDeletionAction } from "./logic";

/** 同時に処理するルームの数（ルームが多い人でも、トランザクションを一度に開きすぎない） */
export const ACCOUNT_DELETION_PARALLEL_ROOMS = 10;

/** 過去のアイデアを消すバッチ 1 つの最大の件数（Firestore のバッチの上限 500 より少なくする） */
export const PAST_IDEA_DELETE_BATCH_SIZE = 400;

/** `deleteAccount` が使う外部のもの */
export interface AccountDeletionDeps extends Pick<ServiceDeps, "db"> {
  /** Auth のユーザーを消す（本番と Emulator では Admin SDK の `getAuth().deleteUser`） */
  deleteAuthUser: (uid: string) => Promise<void>;
}

/** 削除の結果（ログとテストで使う） */
export interface AccountDeletionResult {
  /** 退出と同じに外したルームの数 */
  leftRooms: number;
  /** 終了して外したルーム（作成者のルーム）の数 */
  closedRooms: number;
  /** 消した過去のアイデアの数 */
  deletedPastIdeas: number;
}

/**
 * 1 つのルームから外す（作成者で終了していなければ終了もする）。トランザクションの中で読み直して判定する。
 * @returns 行ったこと（もうメンバーでなければ `none`）
 */
async function leaveRoomForDeletion(db: Firestore, roomId: string, uid: string): Promise<AccountDeletionAction> {
  const ref = roomRef(db, roomId);
  return db.runTransaction(async (tx) => {
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined) {
      return "none";
    }
    const action = accountDeletionActionOf(room, uid);
    switch (action) {
      case "none":
        break;
      case "leave":
        await removeFromRoom(tx, db, ref, room, uid, { notMember: null });
        break;
      case "closeAndLeave":
        await removeFromRoom(tx, db, ref, room, uid, { notMember: null, closing: closedUpdate(room) });
        break;
    }
    return action;
  });
}

/**
 * `users/{uid}/pastIdeas` をすべて消す。
 * @returns 消した数
 */
async function deletePastIdeas(db: Firestore, user: DocumentReference): Promise<number> {
  const ideas = await user.collection("pastIdeas").select().get();
  for (const group of chunk(ideas.docs, PAST_IDEA_DELETE_BATCH_SIZE)) {
    const batch = db.batch();
    for (const doc of group) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
  return ideas.size;
}

/**
 * 呼んだ人のアカウントを削除する（02 の F-06）。入力は使わない（`{}`）。
 * @param deps 外部のもの（Firestore と Auth のユーザーの削除）
 * @param uid 削除する人（呼んだ人）
 * @returns 外したルームと消した過去のアイデアの数
 * @throws `AggregateError`（どれかのルームで失敗したとき。ユーザーのデータは消していない）
 */
export async function deleteAccount(deps: AccountDeletionDeps, uid: string): Promise<AccountDeletionResult> {
  const { db } = deps;
  // ルームの ID だけが要るので、フィールドを読まない（`select()`）
  const rooms = await db.collection("rooms").where("memberIds", "array-contains", uid).select().get();
  const actions = await settleInGroups(rooms.docs, ACCOUNT_DELETION_PARALLEL_ROOMS, (doc) =>
    leaveRoomForDeletion(db, doc.id, uid),
  );

  const user = userRef(db, uid);
  await user.delete();
  const deletedPastIdeas = await deletePastIdeas(db, user);

  try {
    await deps.deleteAuthUser(uid);
  } catch (error) {
    // 前の呼び出しで消し終えていれば成功にする（やり直しても同じ結果）
    if (!isAuthUserNotFound(error)) {
      throw error;
    }
  }
  return {
    leftRooms: actions.filter((action) => action === "leave").length,
    closedRooms: actions.filter((action) => action === "closeAndLeave").length,
    deletedPastIdeas,
  };
}
