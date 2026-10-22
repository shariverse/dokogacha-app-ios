/**
 * プロフィール（`users/{uid}`）の表示名・アバターの色を、ルームの中の複製に反映する判定（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `profileSync.ts` が行い、何をどう書くかはここで決めて Jest で確かめる。
 *
 * 複製があるフィールド（05 の §3）のうち、反映するもの:
 * - `rooms/{roomId}/members/{uid}` の `displayName`・`avatarColor`（05 の §3「プロフィール変更時に Functions が更新」・§5）
 * - `rooms/{roomId}/candidates/{id}` の `postedByName`（投稿者が自分の候補。ルーム画面の候補に今の名前を出す）
 * - `rooms/{roomId}` の `adFreeSponsor.displayName`（自分が購入者のとき。「◯◯さんのおかげで」に今の名前を出す）
 *
 * 反映しないもの: `draws` の `drawnByName`（抽選の記録。重みのスナップショットと同じく、回したときの値を残す）。
 */
import type { AdFreeSponsor, MemberDoc, UserDoc } from "../domain/models";

/** ルームの中に複製しているプロフィールの値 */
export type ProfileCopy = Pick<UserDoc, "displayName" | "avatarColor">;

/**
 * プロフィールの更新で、複製している値（表示名・アバターの色）が変わったか。
 * 通知のトークン（`fcmTokens`）などだけの更新では、ルームを読みに行かない。
 * @param before 更新の前の `users/{uid}`
 * @param after 更新の後の `users/{uid}`
 * @returns 表示名かアバターの色が変わったら true
 */
export function profileCopyChanged(
  before: Partial<ProfileCopy> | undefined,
  after: Partial<ProfileCopy> | undefined,
): boolean {
  if (after === undefined) {
    return false;
  }
  return before?.displayName !== after.displayName || before?.avatarColor !== after.avatarColor;
}

/** 1 つのルームの、反映の前の複製 */
export interface RoomCopies {
  /** ルームのメンバーの uid（`rooms.memberIds`） */
  memberIds: readonly string[];
  /** ルームの広告非表示の購入者（`rooms.adFreeSponsor`） */
  adFreeSponsor?: AdFreeSponsor | null;
  /** 自分のメンバーのドキュメント（無ければ undefined） */
  member: Pick<MemberDoc, "displayName" | "avatarColor"> | undefined;
  /** 自分が投稿した候補（ID と投稿者名） */
  candidates: readonly { id: string; postedByName: string }[];
}

/** 1 つのルームに書く変更 */
export interface RoomCopyUpdates {
  /** メンバーのドキュメントに書く値（変えないなら null） */
  member: Partial<ProfileCopy> | null;
  /** `adFreeSponsor` に書く値（変えないなら null） */
  sponsor: AdFreeSponsor | null;
  /** `postedByName` を書き換える候補の ID */
  candidateIds: string[];
}

/**
 * 1 つのルームで、今のプロフィールに合わせて書き換える複製を決める。
 * すでに今の値なら何も書かない（何度呼んでも同じ結果になり、2 回目からは書き込みが 0 件になる）。
 * 自分がもうメンバーでない（退出した・削除された）ルームには書かない（参加中のルームだけに反映する）。
 * @param uid プロフィールの持ち主
 * @param profile 今のプロフィール
 * @param copies ルームの中の今の複製
 * @returns 書く変更
 */
export function planRoomCopyUpdates(uid: string, profile: ProfileCopy, copies: RoomCopies): RoomCopyUpdates {
  const none: RoomCopyUpdates = { member: null, sponsor: null, candidateIds: [] };
  if (!copies.memberIds.includes(uid) || copies.member === undefined) {
    return none;
  }
  const member: Partial<ProfileCopy> = {};
  if (copies.member.displayName !== profile.displayName) {
    member.displayName = profile.displayName;
  }
  if (copies.member.avatarColor !== profile.avatarColor) {
    member.avatarColor = profile.avatarColor;
  }
  const sponsor = copies.adFreeSponsor;
  return {
    member: Object.keys(member).length === 0 ? null : member,
    sponsor:
      sponsor?.uid === uid && sponsor.displayName !== profile.displayName
        ? { uid, displayName: profile.displayName }
        : null,
    candidateIds: copies.candidates
      .filter((candidate) => candidate.postedByName !== profile.displayName)
      .map((candidate) => candidate.id),
  };
}

/**
 * 変更が書き込むドキュメントの数。
 * @param updates 1 つのルームに書く変更
 * @returns 書き込みの数（メンバー・ルーム・候補の合計）
 */
export function countRoomCopyWrites(updates: RoomCopyUpdates): number {
  return (updates.member === null ? 0 : 1) + (updates.sponsor === null ? 0 : 1) + updates.candidateIds.length;
}

/**
 * 一覧を `size` 件ずつに分ける（ルームを少しずつ並べて処理し、同時に開くトランザクションの数を抑える）。
 * @param items 一覧
 * @param size 1 つの組の最大の件数（1 以上）
 * @returns 組の一覧（元の順を保つ）
 */
export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (!Number.isInteger(size) || size < 1) {
    throw new RangeError(`size は 1 以上の整数: ${String(size)}`);
  }
  const chunks: T[][] = [];
  for (let start = 0; start < items.length; start += size) {
    chunks.push(items.slice(start, start + size));
  }
  return chunks;
}
