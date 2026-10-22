import { HttpsError } from "firebase-functions/v2/https";

import type { RoomStatus } from "../domain/models";
import type { MemberCounts, RoomUnlockState } from "../unlock/logic";
import { decideDraw, drawnEventOf, type DrawableRoom } from "./logic";

/** 判定の時刻の基準 */
const NOW_MS = 1_793_070_000_000;

/** 呼んだ人のメンバーのドキュメント */
const MEMBER = { displayName: "タクミ" };

/** 解禁の判定に使うルームの値（指定しない値は「全員OK・強制解禁なし・引き直しなし」） */
function unlockState(status: RoomStatus, overrides: Partial<RoomUnlockState> = {}): RoomUnlockState {
  return {
    status,
    unlockRule: "all",
    deadlineAtMs: null,
    forcedUnlock: false,
    rerollPassed: false,
    memberCount: 3,
    readyCount: 3,
    ...overrides,
  };
}

/** 数え直した数 */
function counts(memberCount: number, readyCount: number): MemberCounts {
  return { memberCount, readyCount };
}

/** 判定する（ルームの状態と解禁の値の状態をそろえる） */
function decide(
  room: DrawableRoom,
  options: { member?: { displayName: string } | null; unlock?: Partial<RoomUnlockState>; counts?: MemberCounts } = {},
) {
  const member = options.member === null ? undefined : (options.member ?? MEMBER);
  return decideDraw(room, member, unlockState(room.status, options.unlock), options.counts ?? counts(3, 3), NOW_MS);
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

describe("decideDraw（02 の F-40・05 の §5 の drawGacha）", () => {
  it("unlocked で、数え直しても解禁の条件を満たしていれば回せる（回した人の表示名を返す）", () => {
    expect(decide({ status: "unlocked" })).toEqual({ kind: "draw", drawnByName: "タクミ" });
  });

  it("メンバーでなければ not-room-member（状態より先に確かめる）", () => {
    for (const status of ["open", "unlocked", "drawn", "closed"] as const) {
      expectReason(() => decide({ status, currentDrawId: "d1", winnerCandidateId: "c1" }, { member: null }), "not-room-member");
    }
  });

  it("先に誰かが回していたら（drawn）、抽選せずにその抽選の ID と当選を返す", () => {
    expect(decide({ status: "drawn", currentDrawId: "d1", winnerCandidateId: "c1" })).toEqual({
      kind: "alreadyDrawn",
      drawId: "d1",
      candidateId: "c1",
    });
  });

  it("drawn なのに抽選の ID・当選が無い壊れたデータと、closed は room-already-decided", () => {
    expectReason(() => decide({ status: "drawn", currentDrawId: null, winnerCandidateId: "c1" }), "room-already-decided");
    expectReason(() => decide({ status: "drawn", currentDrawId: "d1", winnerCandidateId: "" }), "room-already-decided");
    expectReason(() => decide({ status: "closed", currentDrawId: "d1", winnerCandidateId: "c1" }), "room-already-decided");
  });

  it("知らない状態の壊れたデータは room-not-unlocked（internal にしない）", () => {
    expectReason(() => decide({ status: "broken" as RoomStatus }), "room-not-unlocked");
  });

  it("open は、準備OKが揃っていても room-not-unlocked（トリガーが unlocked にしてから回す）", () => {
    expectReason(() => decide({ status: "open" }), "room-not-unlocked");
  });

  it("unlocked でも、数え直すと条件を満たさない（参加の直後）なら room-not-unlocked", () => {
    expectReason(() => decide({ status: "unlocked" }, { counts: counts(4, 3) }), "room-not-unlocked");
    expectReason(
      () => decide({ status: "unlocked" }, { unlock: { unlockRule: "majority" }, counts: counts(4, 2) }),
      "room-not-unlocked",
    );
  });

  it("強制解禁・締切日時の後・引き直しの可決の後は、準備OKの数によらず回せる", () => {
    expect(decide({ status: "unlocked" }, { unlock: { forcedUnlock: true }, counts: counts(4, 0) }).kind).toBe("draw");
    expect(
      decide(
        { status: "unlocked" },
        { unlock: { unlockRule: "deadline", deadlineAtMs: NOW_MS }, counts: counts(4, 0) },
      ).kind,
    ).toBe("draw");
    expect(decide({ status: "unlocked" }, { unlock: { rerollPassed: true }, counts: counts(4, 0) }).kind).toBe("draw");
  });

  it("締切日時の前（1 ミリ秒前）に unlocked と書いてあっても、数え直すと open なので回せない", () => {
    expectReason(
      () =>
        decide({ status: "unlocked" }, { unlock: { unlockRule: "deadline", deadlineAtMs: NOW_MS + 1 }, counts: counts(3, 0) }),
      "room-not-unlocked",
    );
  });
});

describe("drawnEventOf（onRoomDrawn）", () => {
  it("unlocked から drawn になったら、抽選の ID を返す", () => {
    expect(drawnEventOf({ status: "unlocked", currentDrawId: null }, { status: "drawn", currentDrawId: "d1" })).toEqual({
      drawId: "d1",
    });
  });

  it("引き直しの後にもう一度回して、抽選の ID が変わったときも返す", () => {
    expect(drawnEventOf({ status: "unlocked", currentDrawId: "d1" }, { status: "drawn", currentDrawId: "d2" })).toEqual({
      drawId: "d2",
    });
    expect(drawnEventOf({ status: "drawn", currentDrawId: "d1" }, { status: "drawn", currentDrawId: "d2" })).toEqual({
      drawId: "d2",
    });
  });

  it("drawn のままほかのフィールドだけが変わった更新・drawn でない更新・抽選の ID が無いときは null", () => {
    expect(drawnEventOf({ status: "drawn", currentDrawId: "d1" }, { status: "drawn", currentDrawId: "d1" })).toBeNull();
    expect(drawnEventOf({ status: "open" }, { status: "unlocked" })).toBeNull();
    expect(drawnEventOf({ status: "drawn", currentDrawId: "d1" }, { status: "closed", currentDrawId: "d1" })).toBeNull();
    expect(drawnEventOf({ status: "unlocked" }, { status: "drawn", currentDrawId: null })).toBeNull();
    expect(drawnEventOf(undefined, undefined)).toBeNull();
  });
});
