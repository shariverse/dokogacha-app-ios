/**
 * ルームの解禁の判定を、ルームに書く値に変える（`onMemberWrite`・`forceUnlock`・`checkDeadlines`・`updateRoomSettings` が使う。
 * Firestore に触れない純粋な関数）。判定そのものは `domain/unlock.ts` の `judgeUnlock`・`nextStatusOf`（Swift と同じ式）。
 * Firestore の読み書きは `service.ts` が行う。
 */
import { isOneOf, UNLOCK_RULES, type MemberDoc, type RoomDoc, type RoomStatus } from "../domain/models";
import { judgeUnlock, nextStatusOf, type UnlockReason } from "../domain/unlock";
import { appError } from "../errors";

/** メンバーを数え直した数 */
export interface MemberCounts {
  /** メンバーの数（`members` のドキュメントの数。作成者を含む） */
  memberCount: number;
  /** 準備OKのメンバーの数（`ready` が true のドキュメントの数） */
  readyCount: number;
}

/**
 * `members` のドキュメントを数え直す。`ready` が true のものだけを準備OKに数える（無い・真偽値でないものは数えない）。
 * @param members メンバーのドキュメントの値（`members` のコレクションをまるごと読んだもの）
 * @returns メンバーの数と準備OKの数
 */
export function countMembers(members: readonly Partial<Pick<MemberDoc, "ready">>[]): MemberCounts {
  return { memberCount: members.length, readyCount: members.filter((member) => member.ready === true).length };
}

/**
 * メンバーの書き込みが、数え直しと解禁の判定に関わるか（`onMemberWrite` で判定し直すか）。
 * 作成（参加）・削除（退出・メンバーの削除）と、`ready` の変更だけが関わる。
 * `lastSeenAt`（ルームを開くたびに書く）・表示名の複製（`onUserProfileUpdate`）だけの更新では判定し直さない。
 * @param before 書き込みの前の値（作成なら undefined）
 * @param after 書き込みの後の値（削除なら undefined）
 */
export function memberWriteAffectsUnlock(
  before: Partial<Pick<MemberDoc, "ready">> | undefined,
  after: Partial<Pick<MemberDoc, "ready">> | undefined,
): boolean {
  if (before === undefined || after === undefined) {
    return before !== after;
  }
  return before.ready !== after.ready;
}

/**
 * 解禁の判定に使うルームの値（Firestore から読んだ値を、日時をミリ秒にして渡す）。
 * 壊れたデータでも判定を止めないよう、条件は検証の前の値（`unknown`）で受け取る。
 */
export interface RoomUnlockState {
  /** ルームの今の状態 */
  status: RoomStatus;
  /** 解禁の条件（`settings.unlockRule`。知らない値なら状態を変えない） */
  unlockRule: unknown;
  /** 締切日時のミリ秒（`settings.deadlineAt`。無ければ null） */
  deadlineAtMs: number | null;
  /** 作成者が強制解禁したか（`forcedUnlock`） */
  forcedUnlock: boolean;
  /** 引き直しが可決したか（`reroll.status` が `passed`） */
  rerollPassed: boolean;
  /** 今書いてあるメンバーの数（`memberCount`。数え直した値と違うときだけ書く） */
  memberCount: unknown;
  /** 今書いてある準備OKの数（`readyCount`） */
  readyCount: unknown;
}

/** ルームに書く値（変わるものだけ） */
export interface UnlockUpdate {
  /** 数え直したメンバーの数 */
  memberCount?: number;
  /** 数え直した準備OKの数 */
  readyCount?: number;
  /** 判定し直した状態（`open`⇄`unlocked`） */
  status?: RoomStatus;
}

/** 判定し直した結果 */
export interface UnlockPlan {
  /** ルームに書く値（空なら書かない。冪等: 同じ状態でもう一度呼ぶと空になる） */
  update: UnlockUpdate;
  /** この書き込みで `open` から `unlocked` になったときの理由（解禁の通知に使う。それ以外は null） */
  unlockedBy: UnlockReason | null;
}

/**
 * ルームを数え直した数で判定し直し、書く値を決める（05 の §5 の `onMemberWrite`）。
 *
 * - `memberCount`・`readyCount` は、数え直した値が今の値と違うときだけ書く（増減ではなく数え直しなので、
 *   退出・削除で `readyCount` を減らしていなくても、トリガーが重ねて動いても、正しい値にそろう）
 * - 状態は `nextStatusOf`（`judgeUnlock`）で `open`⇄`unlocked` を決める。判定には数え直した値を使い、`readyCount` のフィールドに頼らない
 * - `drawn`・`closed` は状態を変えない（数だけ数え直す）。条件が壊れている（知らない値）ときも状態を変えない
 * - **引き直しが可決して `unlocked` に戻ったルームは、準備OKの数で `open` に戻さない**
 *   （02 の §6.4「ルームを unlocked に戻す（準備OKはやり直さない）」。戻すと、可決の後に誰かが準備OKを取り消しただけで
 *   もう一度引けなくなる）。可決の後に新しく参加した人がいても `unlocked` のまま
 * @param room ルームの値
 * @param counts 数え直したメンバーの数
 * @param nowMs 今の時刻のミリ秒（締切日時と比べる）
 * @returns 書く値と、解禁したときの理由
 */
export function planUnlock(room: RoomUnlockState, counts: MemberCounts, nowMs: number): UnlockPlan {
  const update: UnlockUpdate = {};
  if (room.memberCount !== counts.memberCount) {
    update.memberCount = counts.memberCount;
  }
  if (room.readyCount !== counts.readyCount) {
    update.readyCount = counts.readyCount;
  }
  if (!isOneOf(UNLOCK_RULES, room.unlockRule) || (room.status === "unlocked" && room.rerollPassed)) {
    return { update, unlockedBy: null };
  }
  const input = {
    status: room.status,
    rule: room.unlockRule,
    memberCount: counts.memberCount,
    readyCount: counts.readyCount,
    deadlineAtMs: room.deadlineAtMs,
    forcedUnlock: room.forcedUnlock,
  };
  const next = nextStatusOf(input, nowMs);
  if (next === room.status) {
    return { update, unlockedBy: null };
  }
  update.status = next;
  const judgement = judgeUnlock(input, nowMs);
  return { update, unlockedBy: judgement.kind === "unlocked" ? judgement.reason : null };
}

/**
 * 数え直した準備OKで判定し直した後の状態（`planUnlock` が書く `status`、書かなければ今の状態）。
 * `drawGacha` が、回す前にトランザクションの中で解禁を確かめるのに使う（`status` のフィールドだけで回させない。
 * 参加の直後は `onMemberWrite` が `open` に戻すまでの数秒、新しい人の準備OK無しで `unlocked` のままになり得るため）。
 * 規則は `planUnlock` と同じ（強制解禁・締切日時・引き直しの可決の後は、準備OKの数で `open` に戻さない）。
 * @param room ルームの値
 * @param counts 数え直したメンバーの数
 * @param nowMs 今の時刻のミリ秒
 */
export function statusAfterRecount(room: RoomUnlockState, counts: MemberCounts, nowMs: number): RoomStatus {
  return planUnlock(room, counts, nowMs).update.status ?? room.status;
}

/** 強制解禁の判定の結果。`unlock` = 強制解禁する・`alreadyUnlocked` = もう解禁している（何も書かない） */
export type ForceUnlockDecision = "unlock" | "alreadyUnlocked";

/**
 * 作成者が強制解禁できるか確かめる（02 の F-32「作成者だけ」「未解禁のとき」）。
 *
 * `unlocked` のときは失敗にせず、何もしない（`alreadyUnlocked`）。作成者が確認ダイアログを開いている間に、
 * 最後の 1 人が準備OKして条件で解禁したときに、トーストを出さずに済ませるため。このとき `forcedUnlock` は立てない
 * （立てると、条件で解禁したルームが取り消しで `open` に戻らなくなる）。
 * @param room ルームの値
 * @param uid 呼んだ人
 * @returns 強制解禁するか
 * @throws `not-room-owner`（作成者でない）・`room-already-decided`（`drawn`・`closed`）
 */
export function decideForceUnlock(room: Pick<RoomDoc, "ownerId" | "status">, uid: string): ForceUnlockDecision {
  if (room.ownerId !== uid) {
    throw appError("not-room-owner");
  }
  if (room.status === "open") {
    return "unlock";
  }
  if (room.status === "unlocked") {
    return "alreadyUnlocked";
  }
  throw appError("room-already-decided");
}
