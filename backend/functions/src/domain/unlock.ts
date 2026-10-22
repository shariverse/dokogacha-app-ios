/**
 * 解禁の判定（02 の §5.2・F-31）と強制解禁（F-32）。
 * Swift 側の `Dokogacha/Domain/Logic/UnlockJudge.swift` と同じ判定で、06 の §2 の同じケースを両方で確かめる。
 *
 * ルームの `status` を書き換えるのはサーバー（`onMemberWrite`・`forceUnlock`・`checkDeadlines`）で、この判定を使う。
 * アプリは同じ判定をヒントの文言（「あと N人」など）にだけ使う。
 */
import type { RoomStatus, UnlockRule } from "./models";

/**
 * 解禁の判定の入力（ルーム 1 つ分）。
 *
 * 準備OKの数は `rooms.readyCount` のフィールドではなく、呼び出し側が数え直した値を渡す
 * （`onMemberWrite` はメンバーの書き込みのたびに数え直す。フィールドは書き込みの順で古い値のことがある）。
 * 日時は UNIX 時刻のミリ秒（`Timestamp.toMillis()`）。
 */
export interface UnlockInput {
  /** ルームの今の状態 */
  readonly status: RoomStatus;
  /** 解禁の条件（`settings.unlockRule`） */
  readonly rule: UnlockRule;
  /** メンバーの数（作成者を含む） */
  readonly memberCount: number;
  /** 準備OKにしているメンバーの数（作成者を含む） */
  readonly readyCount: number;
  /** 締切日時のミリ秒（`settings.deadlineAt`。条件が「締切日時」のときだけ見る。無ければ null） */
  readonly deadlineAtMs: number | null;
  /** 作成者が強制解禁したか（`rooms.forcedUnlock`） */
  readonly forcedUnlock: boolean;
}

/**
 * 解禁した理由。allReady = 全員OK・majorityReady = 過半数OK・deadlinePassed = 締切日時を過ぎた・forced = 強制解禁（F-32）。
 * ヒントの文言と Analytics の `room_unlock` の `forced` を選ぶために返す
 */
export type UnlockReason = "allReady" | "majorityReady" | "deadlinePassed" | "forced";

/**
 * 解禁の判定の結果。
 * - `unlocked`: 解禁している（S-07 の「条件を満たしました。誰が回してもOK！」／「作成者が解禁しました。いつでも回せます」）
 * - `waitingForAll`・`waitingForMajority`: 準備OKを待っている（「全員OKで解禁 · あと N人」「過半数OKで解禁 · あと N人」の N）
 * - `waitingForDeadline`: 締切日時を待っている（「締切 M/D(曜) HH:MM に解禁されます」。締切の無い壊れたデータでは null）
 * - `notApplicable`: 抽選の後（`drawn`・`closed`）。解禁の判定をしない（状態を変えない）
 */
export type UnlockJudgement =
  | { readonly kind: "unlocked"; readonly reason: UnlockReason }
  | { readonly kind: "waitingForAll"; readonly remaining: number }
  | { readonly kind: "waitingForMajority"; readonly remaining: number }
  | { readonly kind: "waitingForDeadline"; readonly deadlineAtMs: number | null }
  | { readonly kind: "notApplicable" };

/** 全員OKに要る人数（メンバーの数。0 人なら 1） */
function allRequired(memberCount: number): number {
  return Math.max(memberCount, 1);
}

/** 過半数OKに要る人数（`OK人数 > メンバー数 ÷ 2` を満たす最小の整数） */
function majorityRequired(memberCount: number): number {
  return Math.floor(Math.max(memberCount, 0) / 2) + 1;
}

/**
 * 解禁に要る準備OKの人数（「全員OK」「過半数OK」のとき）。
 * 全員OKはメンバーの数（0 人なら 1）、過半数OKは `メンバー数 ÷ 2 を切り捨てて + 1`
 * （偶数の 4 人なら 3・奇数の 5 人なら 3・1 人なら 1・20 人なら 11）。締切日時は人数で決まらないので null。
 * @param rule 解禁の条件
 * @param memberCount メンバーの数（作成者を含む）
 */
export function requiredReadyCountOf(rule: UnlockRule, memberCount: number): number | null {
  switch (rule) {
    case "all":
      return allRequired(memberCount);
    case "majority":
      return majorityRequired(memberCount);
    case "deadline":
      return null;
  }
}

/**
 * 解禁しているかと、未解禁ならあと何が要るかを判定する（副作用の無い純粋な関数）。
 *
 * - `drawn`・`closed` は判定しない（`notApplicable`）。`open`・`unlocked` は同じ式で判定し直す
 *   （前の状態に頼らないので、解禁した後に取り消しで条件を満たさなくなれば `open` に戻る。02 の §2.1）
 * - 強制解禁（`forcedUnlock`）は条件によらず解禁。条件も満たしているときも理由は「強制解禁」にする
 * - 全員OK: `OK人数 = メンバー数`。過半数OK: `OK人数 > メンバー数 ÷ 2`（整数で `OK人数 × 2 > メンバー数`）
 * - 締切日時: `今 ≥ 締切日時`（ちょうどで解禁）。準備OKの数は見ない（02 の §5.2「参考表示のみ」）
 *
 * 数が壊れていても判定できるように、メンバーの数は 0 以上、準備OKの数は 0〜メンバーの数に収めてから比べる。
 * メンバーが 0 人のルームは、どの条件でも準備OKが 1 人以上要るので解禁しない。
 * @param input ルームの状態・条件・人数・締切
 * @param nowMs 今の時刻のミリ秒（サーバーでは `Timestamp.now().toMillis()`）
 */
export function judgeUnlock(input: UnlockInput, nowMs: number): UnlockJudgement {
  if (input.status !== "open" && input.status !== "unlocked") {
    return { kind: "notApplicable" };
  }
  if (input.forcedUnlock) {
    return { kind: "unlocked", reason: "forced" };
  }
  const memberCount = Math.max(input.memberCount, 0);
  const readyCount = Math.min(Math.max(input.readyCount, 0), memberCount);
  switch (input.rule) {
    case "all": {
      const remaining = allRequired(memberCount) - readyCount;
      return remaining <= 0 ? { kind: "unlocked", reason: "allReady" } : { kind: "waitingForAll", remaining };
    }
    case "majority": {
      const remaining = majorityRequired(memberCount) - readyCount;
      return remaining <= 0 ? { kind: "unlocked", reason: "majorityReady" } : { kind: "waitingForMajority", remaining };
    }
    case "deadline": {
      const deadlineAtMs = input.deadlineAtMs;
      if (deadlineAtMs === null) {
        return { kind: "waitingForDeadline", deadlineAtMs: null };
      }
      return nowMs >= deadlineAtMs
        ? { kind: "unlocked", reason: "deadlinePassed" }
        : { kind: "waitingForDeadline", deadlineAtMs };
    }
  }
}

/**
 * 判定の後のルームの状態（`onMemberWrite`・`checkDeadlines` が `status` に書く値）。
 * `open`・`unlocked` は解禁していれば `unlocked`、していなければ `open`。`drawn`・`closed` はそのまま。
 * @param input ルームの状態・条件・人数・締切
 * @param nowMs 今の時刻のミリ秒
 */
export function nextStatusOf(input: UnlockInput, nowMs: number): RoomStatus {
  const judgement = judgeUnlock(input, nowMs);
  switch (judgement.kind) {
    case "notApplicable":
      return input.status;
    case "unlocked":
      return "unlocked";
    case "waitingForAll":
    case "waitingForMajority":
    case "waitingForDeadline":
      return "open";
  }
}
