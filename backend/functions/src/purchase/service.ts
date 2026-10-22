/**
 * 広告非表示の購入をサーバーで確かめて記録する（05 の §5 の `verifyPurchase`・02 の §7.2 F-51）。
 * 判定は `logic.ts`、入力の検証は `input.ts`、署名の検証は `verifier.ts`（テストでは差し替える）。
 *
 * 1. 署名付きトランザクションを確かめ、広告非表示のアイテムで取り消されていないことを確かめる
 * 2. 参加しているルーム（状態は問わない）の購入者（`adFreeSponsor`）を、最初に参加した購入者にそろえる
 * 3. `users/{uid}.adFree = true` にする
 *
 * ルームを先にそろえてから `adFree` を書く。アプリは `adFree` が false の間だけこの Callable を呼ぶので、
 * 途中のルームで失敗したら `adFree` を書かずに失敗を返し、次に呼ばれたときにやり直す（どの書き込みも冪等）。
 * 購入した後に参加・作成したルームは、`joinRoom`・`createRoom` が `adFree` を見て購入者を入れる（`sponsorAfterJoin`）。
 */
import type { Firestore, Timestamp } from "firebase-admin/firestore";

import { settleInGroups } from "../batch";
import type { AdFreeSponsor, MemberDoc, RoomDoc, UserDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { membersRef, roomRef, userRef } from "../paths";
import { parseVerifyPurchaseInput } from "./input";
import { decidePurchase, sponsorAfterPurchase, type PurchaseEnvironment } from "./logic";
import type { TransactionVerifier } from "./verifier";

/** 同時に処理するルームの数（参加したルームが多い人でも、トランザクションを一度に開きすぎない） */
export const PURCHASE_SYNC_PARALLEL_ROOMS = 10;

/** `verifyPurchase` の結果（アプリに返すのは `adFree` だけ。ほかはログとテスト用） */
export interface VerifyPurchaseResult {
  /** 広告非表示になったか（受け付けたら常に true） */
  adFree: true;
  /** 署名された環境 */
  environment: PurchaseEnvironment;
  /** 見たルームの数（`memberIds` に自分がいるルーム） */
  rooms: number;
  /** 購入者を書き換えたルームの数 */
  sponsorUpdates: number;
}

/** Firestore の日時をミリ秒にする（無ければ 0。参加の順を比べるのに使う） */
function millisOf(value: Timestamp | undefined): number {
  return value?.toMillis() ?? 0;
}

/**
 * 1 つのルームの購入者を、トランザクションの中で購入した人を含めてそろえる。
 * @returns 書き換えたら true
 */
async function syncRoomSponsor(db: Firestore, uid: string, roomId: string): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const ref = roomRef(db, roomId);
    const room = (await tx.get(ref)).data() as RoomDoc | undefined;
    if (room === undefined || !room.memberIds.includes(uid)) {
      return false;
    }
    const buyer = (await tx.get(membersRef(ref).doc(uid))).data() as MemberDoc | undefined;
    if (buyer === undefined) {
      return false;
    }
    const current: AdFreeSponsor | null = room.adFreeSponsor ?? null;
    let currentJoinedAt: number | null = null;
    if (current !== null && current.uid !== uid) {
      const sponsorMember = (await tx.get(membersRef(ref).doc(current.uid))).data() as MemberDoc | undefined;
      currentJoinedAt = sponsorMember === undefined ? null : millisOf(sponsorMember.joinedAt);
    } else if (current !== null) {
      currentJoinedAt = millisOf(buyer.joinedAt);
    }
    const next = sponsorAfterPurchase({
      current,
      buyer: { uid, displayName: buyer.displayName, joinedAtMs: millisOf(buyer.joinedAt) },
      currentJoin: current === null || currentJoinedAt === null ? null : { uid: current.uid, joinedAtMs: currentJoinedAt },
    });
    if (next === null) {
      return false;
    }
    tx.update(ref, { adFreeSponsor: next });
    return true;
  });
}

/**
 * 広告非表示の購入を確かめて記録する。
 * - 表示名を登録する前（`users/{uid}` が無い）は `profile-required`
 * - 署名を確かめられない・別のアプリのもの・別のアイテム・取り消されたものは `purchase-invalid`
 * - 同じ購入で何度呼んでもよい（復元・端末の入れ替え・匿名のユーザーが替わった後の復元でも、呼んだ人を広告非表示にする）
 * @param deps 外部のもの
 * @param uid 呼んだ人
 * @param data `request.data`（`{ signedTransaction }`）
 * @param verifier 署名の検証（本番は App Store Server Library。テストでは差し替える）
 * @returns 結果
 */
export async function verifyPurchase(
  deps: ServiceDeps,
  uid: string,
  data: unknown,
  verifier: TransactionVerifier,
): Promise<VerifyPurchaseResult> {
  const { signedTransaction } = parseVerifyPurchaseInput(data);
  const { db } = deps;
  const user = userRef(db, uid);
  if (!(await user.get()).exists) {
    throw appError("profile-required");
  }

  const transaction = await verifier.verify(signedTransaction);
  if (decidePurchase(transaction).kind === "reject") {
    throw appError("purchase-invalid");
  }

  // ルームの ID だけが要るので、フィールドを読まない（`select()`）
  const rooms = await db.collection("rooms").where("memberIds", "array-contains", uid).select().get();
  const updated = await settleInGroups(rooms.docs, PURCHASE_SYNC_PARALLEL_ROOMS, (doc) => syncRoomSponsor(db, uid, doc.id));

  await db.runTransaction(async (tx) => {
    const profile = (await tx.get(user)).data() as UserDoc | undefined;
    if (profile === undefined) {
      throw appError("profile-required");
    }
    if (!profile.adFree) {
      tx.update(user, { adFree: true });
    }
  });
  return {
    adFree: true,
    environment: transaction.environment,
    rooms: rooms.size,
    sponsorUpdates: updated.filter(Boolean).length,
  };
}
