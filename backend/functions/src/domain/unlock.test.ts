import type { RoomStatus, UnlockRule } from "./models";
import { UNLOCK_RULES } from "./models";
import {
  judgeUnlock,
  nextStatusOf,
  requiredReadyCountOf,
  type UnlockInput,
  type UnlockJudgement,
} from "./unlock";

// 06 の §2「解禁（F-31）」と強制解禁（F-32）。
// Swift 側の DokogachaTests/UnlockJudgeTests.swift と同じケース。片方を変えたら両方を変える。

/** 判定の時刻の基準（2026-10-27 12:00:00 JST） */
const NOW_MS = 1_793_070_000_000;

/** 入力を作る（指定しない値は「`open`・強制解禁なし・締切なし」） */
function input(
  rule: UnlockRule,
  members: number,
  ready: number,
  options: { status?: RoomStatus; deadlineAtMs?: number; forced?: boolean } = {},
): UnlockInput {
  return {
    status: options.status ?? "open",
    rule,
    memberCount: members,
    readyCount: ready,
    deadlineAtMs: options.deadlineAtMs ?? null,
    forcedUnlock: options.forced ?? false,
  };
}

describe("全員OK・過半数OK", () => {
  // 06 の §2: 全員OK 4/5→未・5/5→解禁、過半数 2/4→未・3/4→解禁・3/5→解禁。加えて過半数の 1 人・20 人
  const countCases: [UnlockRule, number, number, UnlockJudgement][] = [
    ["all", 5, 4, { kind: "waitingForAll", remaining: 1 }],
    ["all", 5, 5, { kind: "unlocked", reason: "allReady" }],
    ["all", 5, 0, { kind: "waitingForAll", remaining: 5 }],
    ["all", 1, 0, { kind: "waitingForAll", remaining: 1 }],
    ["all", 1, 1, { kind: "unlocked", reason: "allReady" }],
    ["majority", 4, 2, { kind: "waitingForMajority", remaining: 1 }],
    ["majority", 4, 3, { kind: "unlocked", reason: "majorityReady" }],
    ["majority", 5, 2, { kind: "waitingForMajority", remaining: 1 }],
    ["majority", 5, 3, { kind: "unlocked", reason: "majorityReady" }],
    ["majority", 1, 0, { kind: "waitingForMajority", remaining: 1 }],
    ["majority", 1, 1, { kind: "unlocked", reason: "majorityReady" }],
    ["majority", 20, 0, { kind: "waitingForMajority", remaining: 11 }],
    ["majority", 20, 10, { kind: "waitingForMajority", remaining: 1 }],
    ["majority", 20, 11, { kind: "unlocked", reason: "majorityReady" }],
  ];

  test.each(countCases)("%s %i 人中 %i 人がOK", (rule, members, ready, expected) => {
    const value = input(rule, members, ready);
    expect(judgeUnlock(value, NOW_MS)).toEqual(expected);
    expect(nextStatusOf(value, NOW_MS)).toBe(expected.kind === "unlocked" ? "unlocked" : "open");
  });

  test("解禁に要る人数（全員OK はメンバーの数、過半数OK は切り捨てて + 1。0 人なら 1。締切日時は null）", () => {
    expect(requiredReadyCountOf("all", 5)).toBe(5);
    expect(requiredReadyCountOf("all", 0)).toBe(1);
    expect(requiredReadyCountOf("majority", 4)).toBe(3);
    expect(requiredReadyCountOf("majority", 5)).toBe(3);
    expect(requiredReadyCountOf("majority", 1)).toBe(1);
    expect(requiredReadyCountOf("majority", 20)).toBe(11);
    expect(requiredReadyCountOf("majority", 0)).toBe(1);
    expect(requiredReadyCountOf("deadline", 5)).toBeNull();
  });

  test("人数の条件では締切日時を見ない（過ぎた締切が残っていても解禁しない）", () => {
    const past = NOW_MS - 60_000;
    expect(judgeUnlock(input("all", 3, 0, { deadlineAtMs: past }), NOW_MS)).toEqual({
      kind: "waitingForAll",
      remaining: 3,
    });
    expect(judgeUnlock(input("majority", 3, 1, { deadlineAtMs: past }), NOW_MS)).toEqual({
      kind: "waitingForMajority",
      remaining: 1,
    });
  });
});

describe("締切日時", () => {
  // 06 の §2「締切：前後1秒」。締切の 1 秒前は未解禁、ちょうどと 1 秒後は解禁（`今 ≥ 締切日時`）
  test.each([
    [-1000, false],
    [0, true],
    [1000, true],
  ])("締切から %i ミリ秒で解禁 = %s", (offsetMs, unlocked) => {
    const deadline = NOW_MS;
    const value = input("deadline", 5, 0, { deadlineAtMs: deadline });
    const expected: UnlockJudgement = unlocked
      ? { kind: "unlocked", reason: "deadlinePassed" }
      : { kind: "waitingForDeadline", deadlineAtMs: deadline };
    expect(judgeUnlock(value, deadline + offsetMs)).toEqual(expected);
    expect(nextStatusOf(value, deadline + offsetMs)).toBe(unlocked ? "unlocked" : "open");
  });

  test("準備OKは参考表示のみ（全員がOKでも締切の前は解禁しない）", () => {
    const deadline = NOW_MS + 1000;
    expect(judgeUnlock(input("deadline", 5, 5, { deadlineAtMs: deadline }), NOW_MS)).toEqual({
      kind: "waitingForDeadline",
      deadlineAtMs: deadline,
    });
  });

  test("締切日時が無い壊れたデータは解禁しない", () => {
    const value = input("deadline", 5, 5);
    expect(judgeUnlock(value, NOW_MS)).toEqual({ kind: "waitingForDeadline", deadlineAtMs: null });
    expect(nextStatusOf(value, NOW_MS)).toBe("open");
  });
});

describe("強制解禁（F-32）", () => {
  // 06 の §2「強制解禁はOK数に関係なく解禁」。どの条件でも、準備OKが 0 人でも、締切の前でも解禁
  test.each(UNLOCK_RULES)("%s でも準備OK 0 人で解禁", (rule) => {
    const value = input(rule, 5, 0, { deadlineAtMs: NOW_MS + 60_000, forced: true });
    expect(judgeUnlock(value, NOW_MS)).toEqual({ kind: "unlocked", reason: "forced" });
    expect(nextStatusOf(value, NOW_MS)).toBe("unlocked");
  });

  test("条件も満たしているときは理由を「強制解禁」にする", () => {
    expect(judgeUnlock(input("all", 3, 3, { forced: true }), NOW_MS)).toEqual({ kind: "unlocked", reason: "forced" });
  });
});

describe("数え直し前の値", () => {
  test("準備OKの数がメンバーの数を超えた入力は、メンバーの数に収めて判定する", () => {
    expect(judgeUnlock(input("all", 5, 6), NOW_MS)).toEqual({ kind: "unlocked", reason: "allReady" });
    expect(judgeUnlock(input("majority", 5, 7), NOW_MS)).toEqual({ kind: "unlocked", reason: "majorityReady" });
  });

  test("負の数は 0 とみなす。メンバーが 0 人のルームは解禁しない", () => {
    expect(judgeUnlock(input("all", 5, -1), NOW_MS)).toEqual({ kind: "waitingForAll", remaining: 5 });
    expect(judgeUnlock(input("all", 0, 0), NOW_MS)).toEqual({ kind: "waitingForAll", remaining: 1 });
    expect(judgeUnlock(input("majority", 0, 0), NOW_MS)).toEqual({ kind: "waitingForMajority", remaining: 1 });
    expect(judgeUnlock(input("all", -1, 2), NOW_MS)).toEqual({ kind: "waitingForAll", remaining: 1 });
  });
});

describe("ルームの状態", () => {
  test("unlocked のルームも判定し直し、条件を満たさなくなれば open に戻る", () => {
    const value = input("all", 5, 4, { status: "unlocked" });
    expect(judgeUnlock(value, NOW_MS)).toEqual({ kind: "waitingForAll", remaining: 1 });
    expect(nextStatusOf(value, NOW_MS)).toBe("open");
  });

  test("強制解禁したルームは、取り消しがあっても unlocked のまま", () => {
    expect(nextStatusOf(input("all", 5, 0, { status: "unlocked", forced: true }), NOW_MS)).toBe("unlocked");
  });

  test.each<RoomStatus>(["drawn", "closed"])("%s は判定せず、状態を変えない", (status) => {
    const past = NOW_MS - 1000;
    const values = [
      input("all", 3, 3, { status }),
      input("majority", 3, 0, { status, forced: true }),
      input("deadline", 3, 0, { status, deadlineAtMs: past }),
    ];
    for (const value of values) {
      expect(judgeUnlock(value, NOW_MS)).toEqual({ kind: "notApplicable" });
      expect(nextStatusOf(value, NOW_MS)).toBe(status);
    }
  });
});
