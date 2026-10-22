import { HttpsError } from "firebase-functions/v2/https";

import type { RoomStatus } from "../domain/models";
import {
  countMembers,
  decideForceUnlock,
  memberWriteAffectsUnlock,
  planUnlock,
  statusAfterRecount,
  type MemberCounts,
  type RoomUnlockState,
} from "./logic";

/** 判定の時刻の基準 */
const NOW_MS = 1_793_070_000_000;

/** ルームの値（指定しない値は「open・全員OK・3 人中 0 人・強制解禁なし・引き直しなし」で、書いてある数は数え直しと同じ） */
function room(overrides: Partial<RoomUnlockState> = {}): RoomUnlockState {
  return {
    status: "open",
    unlockRule: "all",
    deadlineAtMs: null,
    forcedUnlock: false,
    rerollPassed: false,
    memberCount: 3,
    readyCount: 0,
    ...overrides,
  };
}

/** 数え直した数 */
function counts(memberCount: number, readyCount: number): MemberCounts {
  return { memberCount, readyCount };
}

describe("countMembers", () => {
  it("ドキュメントの数をメンバーの数、ready が true のものを準備OKに数える", () => {
    expect(countMembers([{ ready: true }, { ready: false }, { ready: true }])).toEqual(counts(3, 2));
    expect(countMembers([])).toEqual(counts(0, 0));
  });

  it("ready が無い・真偽値でないものは準備OKに数えない", () => {
    expect(countMembers([{}, { ready: "true" as unknown as boolean }, { ready: true }])).toEqual(counts(3, 1));
  });
});

describe("memberWriteAffectsUnlock", () => {
  it("作成（参加）と削除（退出・削除）は判定し直す", () => {
    expect(memberWriteAffectsUnlock(undefined, { ready: false })).toBe(true);
    expect(memberWriteAffectsUnlock({ ready: true }, undefined)).toBe(true);
  });

  it("準備OKの変更だけが判定し直す（lastSeenAt・表示名の複製だけの更新では何もしない）", () => {
    expect(memberWriteAffectsUnlock({ ready: false }, { ready: true })).toBe(true);
    expect(memberWriteAffectsUnlock({ ready: true }, { ready: false })).toBe(true);
    expect(memberWriteAffectsUnlock({ ready: true }, { ready: true })).toBe(false);
    expect(memberWriteAffectsUnlock({ ready: false }, { ready: false })).toBe(false);
  });

  it("前後とも無い（あり得ないイベント）は何もしない", () => {
    expect(memberWriteAffectsUnlock(undefined, undefined)).toBe(false);
  });
});

describe("planUnlock", () => {
  it("全員OK条件で最後の 1 人が準備OKしたら unlocked にし、理由を返す（02 の F-30〜32 の AC）", () => {
    expect(planUnlock(room({ readyCount: 2 }), counts(3, 3), NOW_MS)).toEqual({
      update: { readyCount: 3, status: "unlocked" },
      unlockedBy: "allReady",
    });
  });

  it("解禁の後に誰かが準備OKを取り消すと open に戻る（通知の理由は返さない）", () => {
    expect(planUnlock(room({ status: "unlocked", readyCount: 3 }), counts(3, 2), NOW_MS)).toEqual({
      update: { readyCount: 2, status: "open" },
      unlockedBy: null,
    });
  });

  it("強制解禁したルームは、取り消しても unlocked のまま", () => {
    expect(planUnlock(room({ status: "unlocked", forcedUnlock: true, readyCount: 1 }), counts(3, 0), NOW_MS)).toEqual({
      update: { readyCount: 0 },
      unlockedBy: null,
    });
  });

  it("過半数OK・締切日時でも同じ判定（締切の後は取り消しても unlocked のまま）", () => {
    expect(planUnlock(room({ unlockRule: "majority", readyCount: 1 }), counts(3, 2), NOW_MS)).toEqual({
      update: { readyCount: 2, status: "unlocked" },
      unlockedBy: "majorityReady",
    });
    const passed = room({ status: "unlocked", unlockRule: "deadline", deadlineAtMs: NOW_MS - 1, readyCount: 1 });
    expect(planUnlock(passed, counts(3, 0), NOW_MS)).toEqual({ update: { readyCount: 0 }, unlockedBy: null });
    // 締切を過ぎた open のルーム（checkDeadlines）
    const due = room({ unlockRule: "deadline", deadlineAtMs: NOW_MS });
    expect(planUnlock(due, counts(3, 0), NOW_MS)).toEqual({ update: { status: "unlocked" }, unlockedBy: "deadlinePassed" });
    expect(planUnlock(due, counts(3, 0), NOW_MS - 1)).toEqual({ update: {}, unlockedBy: null });
  });

  it("書いてある数が数え直しと同じで状態も変わらなければ何も書かない（冪等）", () => {
    expect(planUnlock(room({ readyCount: 1 }), counts(3, 1), NOW_MS)).toEqual({ update: {}, unlockedBy: null });
    // 1 回目の結果を書いた後のルームで、もう一度呼ぶ
    const first = planUnlock(room({ readyCount: 2 }), counts(3, 3), NOW_MS);
    const after = room({ readyCount: 3, status: first.update.status ?? "open" });
    expect(planUnlock(after, counts(3, 3), NOW_MS)).toEqual({ update: {}, unlockedBy: null });
  });

  it("退出で数が減ったら数え直す（readyCount を減らしていない退出の後でも正しい数にする）", () => {
    // 4 人中 3 人が準備OKの unlocked でない部屋から、準備OKでない 1 人が抜けると 3 人中 3 人で解禁
    expect(planUnlock(room({ memberCount: 4, readyCount: 3 }), counts(3, 3), NOW_MS)).toEqual({
      update: { memberCount: 3, status: "unlocked" },
      unlockedBy: "allReady",
    });
    // 準備OKの人が抜けても readyCount が残っていた（退出の Callable は数を減らさない）
    expect(planUnlock(room({ memberCount: 3, readyCount: 3, status: "unlocked" }), counts(2, 1), NOW_MS)).toEqual({
      update: { memberCount: 2, readyCount: 1, status: "open" },
      unlockedBy: null,
    });
  });

  it("書いてある数が無い・壊れている（NaN）ときも、数え直した値を書く", () => {
    expect(planUnlock(room({ memberCount: undefined, readyCount: Number.NaN }), counts(2, 0), NOW_MS)).toEqual({
      update: { memberCount: 2, readyCount: 0 },
      unlockedBy: null,
    });
  });

  it("解禁済みのルームに新しい人が参加したら判定し直して open に戻る（02 の F-04。強制解禁なら解禁のまま）", () => {
    expect(planUnlock(room({ status: "unlocked", memberCount: 3, readyCount: 3 }), counts(4, 3), NOW_MS)).toEqual({
      update: { memberCount: 4, status: "open" },
      unlockedBy: null,
    });
    expect(
      planUnlock(room({ status: "unlocked", forcedUnlock: true, memberCount: 3, readyCount: 3 }), counts(4, 3), NOW_MS),
    ).toEqual({ update: { memberCount: 4 }, unlockedBy: null });
  });

  it("引き直しが可決して unlocked に戻ったルームは、準備OKの数で open に戻さない（02 の §6.4「準備OKはやり直さない」）", () => {
    const rerolled = room({ status: "unlocked", rerollPassed: true, readyCount: 3 });
    expect(planUnlock(rerolled, counts(3, 0), NOW_MS)).toEqual({ update: { readyCount: 0 }, unlockedBy: null });
    expect(planUnlock({ ...rerolled, memberCount: 3 }, counts(5, 3), NOW_MS)).toEqual({
      update: { memberCount: 5 },
      unlockedBy: null,
    });
  });

  it.each<RoomStatus>(["drawn", "closed"])("%s は数だけ数え直し、状態を変えない", (status) => {
    expect(planUnlock(room({ status, readyCount: 0 }), counts(3, 3), NOW_MS)).toEqual({
      update: { readyCount: 3 },
      unlockedBy: null,
    });
  });

  it("条件が知らない値（壊れたデータ）なら状態を変えない", () => {
    expect(planUnlock(room({ unlockRule: "someday" }), counts(3, 3), NOW_MS)).toEqual({
      update: { readyCount: 3 },
      unlockedBy: null,
    });
    expect(planUnlock(room({ unlockRule: undefined }), counts(3, 0), NOW_MS)).toEqual({ update: {}, unlockedBy: null });
  });
});

describe("statusAfterRecount（drawGacha が回す前に解禁を確かめる）", () => {
  it("unlocked でも、数え直した準備OKで条件を満たさなければ open（参加の直後で onMemberWrite がまだ戻していない）", () => {
    expect(statusAfterRecount(room({ status: "unlocked", readyCount: 3 }), counts(4, 3), NOW_MS)).toBe("open");
    expect(statusAfterRecount(room({ status: "unlocked", readyCount: 3 }), counts(3, 3), NOW_MS)).toBe("unlocked");
  });

  it("強制解禁・締切日時の後・引き直しの可決の後は、準備OKの数によらず unlocked のまま（planUnlock と同じ規則）", () => {
    expect(statusAfterRecount(room({ status: "unlocked", forcedUnlock: true }), counts(4, 0), NOW_MS)).toBe("unlocked");
    expect(
      statusAfterRecount(
        room({ status: "unlocked", unlockRule: "deadline", deadlineAtMs: NOW_MS - 1 }),
        counts(4, 0),
        NOW_MS,
      ),
    ).toBe("unlocked");
    expect(statusAfterRecount(room({ status: "unlocked", rerollPassed: true }), counts(4, 0), NOW_MS)).toBe("unlocked");
  });

  it("open は条件を満たしていれば unlocked（トリガーより先に揃った）・drawn・closed はそのまま", () => {
    expect(statusAfterRecount(room({ status: "open" }), counts(3, 3), NOW_MS)).toBe("unlocked");
    expect(statusAfterRecount(room({ status: "drawn" }), counts(3, 0), NOW_MS)).toBe("drawn");
    expect(statusAfterRecount(room({ status: "closed" }), counts(3, 3), NOW_MS)).toBe("closed");
  });
});

describe("decideForceUnlock（02 の F-32）", () => {
  /** 理由つきのエラーで失敗することを確かめる */
  function expectReason(run: () => unknown, reason: string): void {
    expect(run).toThrow(HttpsError);
    try {
      run();
    } catch (error) {
      expect((error as HttpsError).details).toEqual({ reason });
    }
  }

  it("作成者は open のルームを強制解禁できる", () => {
    expect(decideForceUnlock({ ownerId: "alice", status: "open" }, "alice")).toBe("unlock");
  });

  it("もう unlocked なら何もしない（失敗にしない）", () => {
    expect(decideForceUnlock({ ownerId: "alice", status: "unlocked" }, "alice")).toBe("alreadyUnlocked");
  });

  it("作成者以外は強制解禁できない（状態より先に確かめる）", () => {
    expectReason(() => decideForceUnlock({ ownerId: "alice", status: "open" }, "bob"), "not-room-owner");
    expectReason(() => decideForceUnlock({ ownerId: "alice", status: "drawn" }, "bob"), "not-room-owner");
  });

  it.each<RoomStatus>(["drawn", "closed"])("%s では強制解禁できない", (status) => {
    expectReason(() => decideForceUnlock({ ownerId: "alice", status }, "alice"), "room-already-decided");
  });
});
