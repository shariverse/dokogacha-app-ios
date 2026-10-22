/**
 * ルームの作成・参加・退出・メンバー削除（05 の §5 の `createRoom`・`joinRoom`・`leaveRoom`・`removeMember`）。
 * 整合性が要る書き込み（招待コードの確保・人数の上限・カウント・いいねの除去）を、トランザクションでまとめて行う。
 * 判定は `logic.ts`、入力の検証は `input.ts` に切り出してある。
 *
 * 解禁の再判定（05 の §5）と `readyCount` の数え直しは、members の作成・削除で動く `onMemberWrite`（タスク 23）が受け持つ。
 * ここでは `readyCount` に触れない（増やす経路と減らす経路を `onMemberWrite` の数え直しの 1 か所にそろえ、
 * 準備OKの人が退出したときに数がずれたり負になったりしないようにする）。
 */
import {
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";

import type { MemberDoc, RoomDoc, UserDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError, type AppErrorReason } from "../errors";
import { candidatesRef, inviteCodeRef, membersRef, roomRef, userRef } from "../paths";
import { planAfterLeave, rerollUpdateOf } from "../reroll/logic";
import { parseCreateRoomInput, parseJoinRoomInput, parseLeaveRoomInput, parseRemoveMemberInput } from "./input";
import {
  allocateInviteCode,
  assertCanLeave,
  assertCanRemove,
  assertJoinable,
  newMemberDoc,
  newRoomDoc,
  roomPreview,
  sponsorAfterJoin,
  sponsorAfterRemoval,
  type RoomPreview,
  type SponsorCandidate,
} from "./logic";

/**
 * トランザクションの中で、呼んだ人のプロフィールを読む。無ければ `profile-required`（S-01 で表示名を登録していない）。
 */
async function getProfile(tx: Transaction, db: Firestore, uid: string): Promise<UserDoc> {
  const profile = (await tx.get(userRef(db, uid))).data() as UserDoc | undefined;
  if (profile === undefined) {
    throw appError("profile-required");
  }
  return profile;
}

/**
 * トランザクションの中で、ルームを読む。無ければ `notFound` の理由で失敗する。
 */
async function getRoom(tx: Transaction, ref: DocumentReference, notFound: AppErrorReason): Promise<RoomDoc> {
  const room = (await tx.get(ref)).data() as RoomDoc | undefined;
  if (room === undefined) {
    throw appError(notFound);
  }
  return room;
}

/** `createRoom` の結果 */
export interface CreateRoomResult {
  /** 作ったルームの ID */
  roomId: string;
  /** 招待コード（ハイフンなしの 6 文字。表示はアプリが `ABC-123` の形にする） */
  inviteCode: string;
}

/**
 * ルームを作る（02 の F-02）。招待コードを確保し、ルームと作成者のメンバーを同じトランザクションで作る。
 * 招待コードが使用済み（`inviteCodes/{code}` がある）なら、コードを作り直して別のトランザクションでやり直す。
 * @param deps 外部のもの
 * @param uid 作成者
 * @param data `request.data`（`{ name, postLimit, unlockRule, deadlineAt?, likeMode }`）
 * @returns ルームの ID と招待コード
 */
export async function createRoom(deps: ServiceDeps, uid: string, data: unknown): Promise<CreateRoomResult> {
  const input = parseCreateRoomInput(data, deps.nowMs());
  const { db } = deps;
  const room = db.collection("rooms").doc();

  const inviteCode = await allocateInviteCode(
    (code) =>
      db.runTransaction(async (tx) => {
        const codeRef = inviteCodeRef(db, code);
        const profile = await getProfile(tx, db, uid);
        if ((await tx.get(codeRef)).exists) {
          return false;
        }
        const now = FieldValue.serverTimestamp();
        const owner: SponsorCandidate = { uid, displayName: profile.displayName, adFree: profile.adFree };
        tx.create(codeRef, { roomId: room.id, createdAt: now });
        tx.create(room, newRoomDoc(input, owner, code, now, (ms) => Timestamp.fromMillis(ms)));
        tx.create(membersRef(room).doc(uid), newMemberDoc(profile, "owner", now));
        return true;
      }),
    deps.random,
  );
  return { roomId: room.id, inviteCode };
}

/** `joinRoom` の結果 */
export interface JoinRoomResult {
  /** 参加したルームの ID */
  roomId: string;
  /** もとからメンバーだったか（S-06「すでにメンバーなら確認を出さずにルーム画面へ」。そのときは何も書き換えない） */
  alreadyMember: boolean;
}

/**
 * 招待コードでルームに参加する（02 の F-04）。
 * 状態（`open`・`unlocked`）と人数（20 人未満）を確かめ、メンバーを作って `memberIds`・`memberCount`・広告の購入者を更新する。
 * @param deps 外部のもの
 * @param uid 参加する人
 * @param data `request.data`（`{ inviteCode }`。小文字・ハイフン・全角を受け付ける）
 * @returns ルームの ID
 */
export async function joinRoom(deps: ServiceDeps, uid: string, data: unknown): Promise<JoinRoomResult> {
  const { inviteCode } = parseJoinRoomInput(data);
  const { db } = deps;
  return db.runTransaction(async (tx) => {
    const profile = await getProfile(tx, db, uid);
    const codeEntry = (await tx.get(inviteCodeRef(db, inviteCode))).data() as { roomId?: unknown } | undefined;
    if (typeof codeEntry?.roomId !== "string") {
      throw appError("invite-code-not-found");
    }
    const ref = roomRef(db, codeEntry.roomId);
    const room = await getRoom(tx, ref, "invite-code-not-found");
    const memberRef = membersRef(ref).doc(uid);
    if ((await tx.get(memberRef)).exists) {
      return { roomId: ref.id, alreadyMember: true };
    }
    assertJoinable(room);

    const joiner: SponsorCandidate = { uid, displayName: profile.displayName, adFree: profile.adFree };
    const sponsor = sponsorAfterJoin(room.adFreeSponsor, joiner);
    tx.create(memberRef, newMemberDoc(profile, "member", FieldValue.serverTimestamp()));
    tx.update(ref, {
      memberIds: FieldValue.arrayUnion(uid),
      memberCount: FieldValue.increment(1),
      adFreeSponsor: sponsor,
    });
    return { roomId: ref.id, alreadyMember: false };
  });
}

/**
 * 招待コードで参加する前に、参加するルームを確かめる（03 の S-06 参加確認。02 の F-04）。
 * メンバー以外はルームを読めない（セキュリティルール）ので、S-06 に出す値をここで返す。何も書き込まない。
 *
 * 入力の検証（招待コードの正規化）・コードからルームを引く・参加できるかの判定は `joinRoom` と同じで、
 * 断るときの理由と文言も同じ（存在しない・形が正しくないコードは「招待コードが見つかりません」、満員、決定後）。
 * 表示名の登録（`profile-required`）は確かめない（読むだけなので。参加は `joinRoom` が確かめる）。
 * @param deps 外部のもの
 * @param uid 呼んだ人
 * @param data `request.data`（`{ inviteCode }`。小文字・ハイフン・全角を受け付ける）
 * @returns S-06 に出すルームの値
 */
export async function previewRoom(deps: ServiceDeps, uid: string, data: unknown): Promise<RoomPreview> {
  const { inviteCode } = parseJoinRoomInput(data);
  const { db } = deps;
  const codeEntry = (await inviteCodeRef(db, inviteCode).get()).data() as { roomId?: unknown } | undefined;
  if (typeof codeEntry?.roomId !== "string") {
    throw appError("invite-code-not-found");
  }
  const ref = roomRef(db, codeEntry.roomId);
  const room = (await ref.get()).data() as RoomDoc | undefined;
  if (room === undefined) {
    throw appError("invite-code-not-found");
  }
  const [member, owner] = await Promise.all([membersRef(ref).doc(uid).get(), membersRef(ref).doc(room.ownerId).get()]);
  const ownerName = (owner.data() as MemberDoc | undefined)?.displayName ?? null;
  return roomPreview(ref.id, room, ownerName, member.exists);
}

/**
 * トランザクションの中で、メンバーをルームから外す（退出と削除で共通。02 の F-05「挙動は退出と同じ」）。
 * - メンバーのドキュメントを消し、`memberIds`・`memberCount` を更新する（`readyCount` は `onMemberWrite` が数え直す）
 * - その人のいいねを全候補の `likedBy` から取り除く（候補そのものは残す）
 * - 引き直しの投票（`reroll.votesFor`・`votesAgainst`）からも取り除く（残ると人数と票が合わなくなる）。
 *   投票中なら残りのメンバーで判定し直し、賛成が過半数になれば可決する（`planAfterLeave`）
 * - 広告非表示の購入者だったら、残りのメンバーから参加の早い順に探し直す
 *
 * トランザクションは読み取りを書き込みより先に済ませる決まりなので、読み取りをすべて終えてから書く。
 *
 * アカウントの削除（`account/service.ts`）では、作成者のルームを終了する書き込み（`options.closing`）を同じ更新に重ねる。
 * そのときは引き直しの判定し直しをしない（終了の書き込みが投票中の引き直しを否決にするので、可決させて `unlocked` に戻さない）。
 * また、メンバーのドキュメントが無くても失敗にしない（`options.notMember` が null。`memberIds` などから取り除くだけにする）。
 * @param tx トランザクション
 * @param db Firestore
 * @param ref ルーム
 * @param room ルームの値（同じトランザクションで読んだもの）
 * @param memberId 外す人
 * @param options 外す人がメンバーでないときの理由（null なら失敗にしない）と、同じ更新で書くルームの終了
 */
export async function removeFromRoom(
  tx: Transaction,
  db: Firestore,
  ref: DocumentReference,
  room: RoomDoc,
  memberId: string,
  options: { notMember: AppErrorReason | null; closing?: Record<string, unknown> },
): Promise<void> {
  const memberRef = membersRef(ref).doc(memberId);
  const member = (await tx.get(memberRef)).data() as MemberDoc | undefined;
  if (member === undefined && options.notMember !== null) {
    throw appError(options.notMember);
  }

  const sponsorChanges = room.adFreeSponsor?.uid === memberId;
  let sponsor = room.adFreeSponsor ?? null;
  if (sponsorChanges) {
    const remaining = (await tx.get(membersRef(ref).orderBy("joinedAt"))).docs.filter((doc) => doc.id !== memberId);
    const users = remaining.length === 0 ? [] : await tx.getAll(...remaining.map((doc) => userRef(db, doc.id)));
    const candidates = remaining.map((doc, index): SponsorCandidate => ({
      uid: doc.id,
      displayName: (doc.data() as MemberDoc).displayName,
      adFree: (users[index]?.data() as UserDoc | undefined)?.adFree === true,
    }));
    sponsor = sponsorAfterRemoval(sponsor, memberId, candidates);
  }
  const liked = await tx.get(candidatesRef(ref).where("likedBy", "array-contains", memberId));

  // ネストしたフィールド（`reroll.votesFor`）を書くので、キーを文字列で持つ
  const update: Record<string, unknown> = {
    memberIds: FieldValue.arrayRemove(memberId),
    "reroll.votesFor": FieldValue.arrayRemove(memberId),
    "reroll.votesAgainst": FieldValue.arrayRemove(memberId),
  };
  if (member !== undefined) {
    tx.delete(memberRef);
    update.memberCount = FieldValue.increment(-1);
  }
  if (options.closing !== undefined) {
    Object.assign(update, options.closing);
  } else {
    // 引き直しの投票中なら、残りのメンバーで判定し直す（賛成が過半数になれば、その場で可決して unlocked に戻す）
    const reroll = planAfterLeave(room, memberId);
    if (reroll !== null) {
      Object.assign(update, rerollUpdateOf(reroll));
    }
  }
  if (sponsorChanges) {
    update.adFreeSponsor = sponsor;
  }
  tx.update(ref, update);
  for (const candidate of liked.docs) {
    tx.update(candidate.ref, { likedBy: FieldValue.arrayRemove(memberId) });
  }
}

/**
 * ルームから退出する（02 の F-05「メンバーはいつでも退出できる」「作成者は退出できない」）。
 * @param deps 外部のもの
 * @param uid 退出する人
 * @param data `request.data`（`{ roomId }`）
 */
export async function leaveRoom(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId } = parseLeaveRoomInput(data);
  const { db } = deps;
  const ref = roomRef(db, roomId);
  await db.runTransaction(async (tx) => {
    const room = await getRoom(tx, ref, "room-not-found");
    assertCanLeave(room, uid);
    await removeFromRoom(tx, db, ref, room, uid, { notMember: "not-room-member" });
  });
  return {};
}

/**
 * 作成者がメンバーを削除する（02 の F-05「作成者はメンバーを削除できる（挙動は退出と同じ）」）。
 * @param deps 外部のもの
 * @param uid 呼んだ人（作成者であること）
 * @param data `request.data`（`{ roomId, memberId }`）
 */
export async function removeMember(deps: ServiceDeps, uid: string, data: unknown): Promise<Record<string, never>> {
  const { roomId, memberId } = parseRemoveMemberInput(data);
  const { db } = deps;
  const ref = roomRef(db, roomId);
  await db.runTransaction(async (tx) => {
    const room = await getRoom(tx, ref, "room-not-found");
    assertCanRemove(room, uid, memberId);
    await removeFromRoom(tx, db, ref, room, memberId, { notMember: "member-not-found" });
  });
  return {};
}
