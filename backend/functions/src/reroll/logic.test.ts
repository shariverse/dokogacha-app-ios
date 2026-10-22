import { HttpsError } from "firebase-functions/v2/https";

import { REROLL_VOTING_DURATION_MS } from "../domain/constants";
import type { RoomStatus } from "../domain/models";
import {
  excludedAfterPass,
  planAfterLeave,
  planExpiry,
  planPropose,
  planVote,
  rerollUpdateOf,
  type RerollRoom,
} from "./logic";

/** 判定の時刻の基準 */
const NOW_MS = 1_793_070_000_000;

/** 4 人の drawn のルーム（指定しない値は「提案前・当選 c1・除外なし」） */
function room(overrides: Partial<RerollRoom> = {}): RerollRoom {
  return {
    status: "drawn",
    memberIds: ["a", "b", "c", "d"],
    winnerCandidateId: "c1",
    excludedCandidateIds: [],
    reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
    ...overrides,
  };
}

/** 投票中のルーム */
function voting(votesFor: string[], votesAgainst: string[] = [], overrides: Partial<RerollRoom> = {}): RerollRoom {
  return room({ reroll: { used: true, proposedBy: votesFor[0] ?? "a", votesFor, votesAgainst, status: "voting" }, ...overrides });
}

/** 理由つきのエラーで失敗することを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  let caught: unknown;
  try {
    run();
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(HttpsError);
  expect((caught as HttpsError).details).toEqual({ reason });
}

describe("planPropose（02 の §6.4・F-43）", () => {
  it("drawn で提案前なら提案でき、提案者は自動で賛成（4 人で 1 人の賛成は投票中）", () => {
    expect(planPropose(room(), "b")).toEqual({
      kind: "propose",
      plan: { votesFor: ["b"], votesAgainst: [], status: "voting", excludedCandidateIds: null },
    });
  });

  it("1 人のルームは、提案者の賛成だけで過半数なのでその場で可決し、当選を除外リストに足す", () => {
    expect(planPropose(room({ memberIds: ["a"], excludedCandidateIds: ["c0"] }), "a")).toEqual({
      kind: "propose",
      plan: { votesFor: ["a"], votesAgainst: [], status: "passed", excludedCandidateIds: ["c0", "c1"] },
    });
  });

  it("メンバーでなければ not-room-member（状態より先に確かめる）", () => {
    for (const status of ["open", "unlocked", "drawn", "closed"] as const) {
      expectReason(() => planPropose(room({ status }), "x"), "not-room-member");
    }
  });

  it("closed は room-closed", () => {
    expectReason(() => planPropose(room({ status: "closed" }), "a"), "room-closed");
  });

  it("ほかの人が先に提案して投票中なら、提案の代わりに賛成の票として数える", () => {
    expect(planPropose(voting(["a"], ["b"]), "b")).toEqual({
      kind: "approve",
      plan: { votesFor: ["a", "b"], votesAgainst: [], status: "voting", excludedCandidateIds: null },
    });
  });

  it("F-43 の AC: 可決・否決の後は 2 回目を提案できない（reroll-used）", () => {
    const passed = room({ status: "unlocked", reroll: { used: true, votesFor: ["a", "b", "c"], votesAgainst: [], status: "passed" } });
    expectReason(() => planPropose(passed, "a"), "reroll-used");
    // 可決の後にもう一度回して drawn になっても使用済み
    expectReason(() => planPropose({ ...passed, status: "drawn" }, "a"), "reroll-used");
    const rejected = room({ reroll: { used: true, votesFor: ["a"], votesAgainst: [], status: "rejected" } });
    expectReason(() => planPropose(rejected, "b"), "reroll-used");
    // 状態が none でも、権利を使った印があれば使用済み
    expectReason(() => planPropose(room({ reroll: { used: true, votesFor: [], votesAgainst: [], status: "none" } }), "a"), "reroll-used");
  });

  it("open・unlocked（行き先が決まる前）は room-not-drawn", () => {
    for (const status of ["open", "unlocked"] as const satisfies RoomStatus[]) {
      expectReason(() => planPropose(room({ status }), "a"), "room-not-drawn");
    }
  });

  it("reroll が無い壊れたデータでも、drawn なら提案できる", () => {
    expect(planPropose(room({ reroll: null }), "a").kind).toBe("propose");
  });
});

describe("planVote", () => {
  it("賛成の票を足す。過半数（> 4 ÷ 2）の 3 人目で可決し、直前の当選を除外リストに足す", () => {
    expect(planVote(voting(["a"]), "b", true)).toEqual({
      votesFor: ["a", "b"],
      votesAgainst: [],
      status: "voting",
      excludedCandidateIds: null,
    });
    expect(planVote(voting(["a", "b"], ["d"]), "c", true)).toEqual({
      votesFor: ["a", "b", "c"],
      votesAgainst: ["d"],
      status: "passed",
      excludedCandidateIds: ["c1"],
    });
  });

  it("反対の票を足す。全員が投票しても、期限までは否決にしない（票を変えられるため）", () => {
    expect(planVote(voting(["a"], ["b", "c"]), "d", false)).toEqual({
      votesFor: ["a"],
      votesAgainst: ["b", "c", "d"],
      status: "voting",
      excludedCandidateIds: null,
    });
  });

  it("1 人 1 票: 票を変えると前の票を取り除く。同じ票をもう一度送っても変わらない", () => {
    expect(planVote(voting(["a", "b"]), "b", false)).toMatchObject({ votesFor: ["a"], votesAgainst: ["b"] });
    expect(planVote(voting(["a"], ["b"]), "b", true)).toMatchObject({ votesFor: ["a", "b"], votesAgainst: [] });
    expect(planVote(voting(["a", "b"]), "b", true)).toMatchObject({ votesFor: ["a", "b"], votesAgainst: [] });
    // 提案者も反対に変えられる
    expect(planVote(voting(["a"]), "a", false)).toMatchObject({ votesFor: [], votesAgainst: ["a"] });
  });

  it("退出した人の票・重なった票は数えずに書き直す", () => {
    expect(planVote(voting(["a", "left", "a"], ["gone"]), "b", true)).toMatchObject({
      votesFor: ["a", "b"],
      votesAgainst: [],
      status: "voting",
    });
  });

  it("メンバーでなければ not-room-member・closed は room-closed", () => {
    expectReason(() => planVote(voting(["a"]), "x", true), "not-room-member");
    expectReason(() => planVote(voting(["a"], [], { status: "closed" }), "a", true), "room-closed");
  });

  it("投票中でない（提案前・可決・否決の後・drawn でない）なら reroll-not-voting", () => {
    expectReason(() => planVote(room(), "a", true), "reroll-not-voting");
    for (const status of ["passed", "rejected"] as const) {
      expectReason(() => planVote(room({ reroll: { used: true, votesFor: [], votesAgainst: [], status } }), "a", true), "reroll-not-voting");
    }
    expectReason(() => planVote(voting(["a"], [], { status: "unlocked" }), "b", true), "reroll-not-voting");
  });
});

describe("planExpiry（提案から 24 時間で否決。06 の §4 の仮決め）", () => {
  const proposedAt = NOW_MS - REROLL_VOTING_DURATION_MS;

  it("24 時間ちょうどで、過半数に届いていなければ否決（票は残し、除外リストは変えない）", () => {
    expect(planExpiry(voting(["a", "b"], ["c"]), proposedAt, NOW_MS)).toEqual({
      votesFor: ["a", "b"],
      votesAgainst: ["c"],
      status: "rejected",
      excludedCandidateIds: null,
    });
  });

  it("24 時間の 1 ミリ秒前は何もしない", () => {
    expect(planExpiry(voting(["a"]), proposedAt + 1, NOW_MS)).toBeNull();
  });

  it("投票中でなければ何もしない", () => {
    expect(planExpiry(room(), proposedAt, NOW_MS)).toBeNull();
    expect(planExpiry(room({ reroll: { used: true, votesFor: [], votesAgainst: [], status: "rejected" } }), 0, NOW_MS)).toBeNull();
  });

  it("提案の日時が無い壊れたデータは、期限を過ぎたものとして否決する", () => {
    expect(planExpiry(voting(["a"]), null, NOW_MS)?.status).toBe("rejected");
  });

  it("期限の時点で過半数なら（取りこぼした判定）可決にする。drawn でなければ否決", () => {
    expect(planExpiry(voting(["a", "b", "c"]), proposedAt, NOW_MS)).toMatchObject({ status: "passed", excludedCandidateIds: ["c1"] });
    expect(planExpiry(voting(["a", "b", "c"], [], { status: "unlocked" }), proposedAt, NOW_MS)?.status).toBe("rejected");
  });
});

describe("planAfterLeave（投票中にメンバーが外れた）", () => {
  it("残りのメンバーで過半数なら可決する（賛成 2 / 4 人 → 反対していない人が外れて 2 / 3 人）", () => {
    expect(planAfterLeave(voting(["a", "b"]), "d")).toEqual({
      votesFor: ["a", "b"],
      votesAgainst: [],
      status: "passed",
      excludedCandidateIds: ["c1"],
    });
  });

  it("外れた人の票を取り除き、過半数でなければ投票中のまま", () => {
    expect(planAfterLeave(voting(["a", "b"], ["c"]), "b")).toEqual({
      votesFor: ["a"],
      votesAgainst: ["c"],
      status: "voting",
      excludedCandidateIds: null,
    });
  });

  it("投票中でない・drawn でないなら null", () => {
    expect(planAfterLeave(room(), "a")).toBeNull();
    expect(planAfterLeave(voting(["a"], [], { status: "unlocked" }), "b")).toBeNull();
  });
});

describe("excludedAfterPass・rerollUpdateOf", () => {
  it("直前の当選を除外リストの末尾に足す（重ねない・当選が無ければ今のまま）", () => {
    expect(excludedAfterPass({ winnerCandidateId: "c2", excludedCandidateIds: ["c1"] })).toEqual(["c1", "c2"]);
    expect(excludedAfterPass({ winnerCandidateId: "c1", excludedCandidateIds: ["c1"] })).toEqual(["c1"]);
    expect(excludedAfterPass({ winnerCandidateId: null, excludedCandidateIds: ["c1"] })).toEqual(["c1"]);
    expect(excludedAfterPass({ winnerCandidateId: "c1", excludedCandidateIds: "broken" })).toEqual(["c1"]);
  });

  it("可決なら unlocked に戻して除外リストを書く。準備OKには触れない", () => {
    expect(rerollUpdateOf({ votesFor: ["a"], votesAgainst: [], status: "passed", excludedCandidateIds: ["c1"] })).toEqual({
      "reroll.votesFor": ["a"],
      "reroll.votesAgainst": [],
      "reroll.status": "passed",
      status: "unlocked",
      excludedCandidateIds: ["c1"],
    });
    expect(rerollUpdateOf({ votesFor: ["a"], votesAgainst: ["b"], status: "voting", excludedCandidateIds: null })).toEqual({
      "reroll.votesFor": ["a"],
      "reroll.votesAgainst": ["b"],
      "reroll.status": "voting",
    });
  });
});
