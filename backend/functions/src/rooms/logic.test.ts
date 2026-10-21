import { MAX_MEMBERS } from "../domain/constants";
import {
  allocateInviteCode,
  assertCanLeave,
  assertCanRemove,
  assertJoinable,
  MAX_INVITE_CODE_ATTEMPTS,
  newMemberDoc,
  newRoomDoc,
  sponsorAfterJoin,
  sponsorAfterRemoval,
  type SponsorCandidate,
} from "./logic";

/** 関数が指定した理由の HttpsError を投げることを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  expect(run).toThrow(expect.objectContaining({ details: { reason } }) as Error);
}

/** 呼ぶたびに、並びの値を順に返す乱数（1 回の招待コードで 6 回呼ばれる） */
function sequence(values: number[]): (max: number) => number {
  let index = 0;
  return () => values[index++ % values.length] ?? 0;
}

describe("allocateInviteCode（05 の §3「コード重複時は再生成」）", () => {
  it("確保できたコードを返す", async () => {
    await expect(allocateInviteCode(() => Promise.resolve(true), () => 0)).resolves.toBe("AAAAAA");
  });

  it("使用済みのコードは作り直す", async () => {
    const tried: string[] = [];
    // 1 回目は AAAAAA（使用済み）、2 回目は BBBBBB
    const random = sequence([0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]);
    const code = await allocateInviteCode((candidate) => {
      tried.push(candidate);
      return Promise.resolve(candidate !== "AAAAAA");
    }, random);
    expect(code).toBe("BBBBBB");
    expect(tried).toEqual(["AAAAAA", "BBBBBB"]);
  });

  it("上限の回数まで重複したら invite-code-unavailable", async () => {
    const reserve = jest.fn(() => Promise.resolve(false));
    await expect(allocateInviteCode(reserve, () => 0)).rejects.toMatchObject({
      code: "unavailable",
      details: { reason: "invite-code-unavailable" },
    });
    expect(reserve).toHaveBeenCalledTimes(MAX_INVITE_CODE_ATTEMPTS);
  });
});

describe("assertJoinable（02 の F-04 の参加条件）", () => {
  it("open・unlocked で 20 人未満なら参加できる", () => {
    expect(() => {
      assertJoinable({ status: "open", memberCount: 1 });
    }).not.toThrow();
    expect(() => {
      assertJoinable({ status: "unlocked", memberCount: MAX_MEMBERS - 1 });
    }).not.toThrow();
  });

  it("20 人のルームには参加できない（21 人目）", () => {
    expectReason(() => {
      assertJoinable({ status: "open", memberCount: MAX_MEMBERS });
    }, "room-full");
  });

  it("drawn・closed には参加できない（満員でも状態の理由を先に返す）", () => {
    for (const status of ["drawn", "closed"] as const) {
      expectReason(() => {
        assertJoinable({ status, memberCount: 2 });
      }, "room-already-decided");
      expectReason(() => {
        assertJoinable({ status, memberCount: MAX_MEMBERS });
      }, "room-already-decided");
    }
  });
});

const alice: SponsorCandidate = { uid: "alice", displayName: "ありす", adFree: true };
const bob: SponsorCandidate = { uid: "bob", displayName: "ぼぶ", adFree: false };
const carol: SponsorCandidate = { uid: "carol", displayName: "きゃろる", adFree: true };

describe("広告非表示の購入者（05 の §3「購入者がいれば最初に参加した人」）", () => {
  it("参加: 購入者がいなければ、購入済みの参加者がなる", () => {
    expect(sponsorAfterJoin(null, alice)).toEqual({ uid: "alice", displayName: "ありす" });
    expect(sponsorAfterJoin(undefined, bob)).toBeNull();
  });

  it("参加: すでに購入者がいれば変えない（先に参加した人）", () => {
    expect(sponsorAfterJoin({ uid: "alice", displayName: "ありす" }, carol)).toEqual({ uid: "alice", displayName: "ありす" });
  });

  it("退出: 購入者が抜けたら、残りから参加の早い順に探し直す", () => {
    const current = { uid: "alice", displayName: "ありす" };
    expect(sponsorAfterRemoval(current, "alice", [bob, carol])).toEqual({ uid: "carol", displayName: "きゃろる" });
    expect(sponsorAfterRemoval(current, "alice", [bob])).toBeNull();
  });

  it("退出: 購入者以外が抜けても変えない", () => {
    const current = { uid: "alice", displayName: "ありす" };
    expect(sponsorAfterRemoval(current, "bob", [alice, carol])).toBe(current);
  });
});

describe("退出と削除（02 の F-05）", () => {
  const room = { ownerId: "alice" };

  it("作成者は退出できない", () => {
    expectReason(() => {
      assertCanLeave(room, "alice");
    }, "owner-cannot-leave");
    expect(() => {
      assertCanLeave(room, "bob");
    }).not.toThrow();
  });

  it("メンバーを削除できるのは作成者だけ", () => {
    expectReason(() => {
      assertCanRemove(room, "bob", "carol");
    }, "not-room-owner");
    expect(() => {
      assertCanRemove(room, "alice", "bob");
    }).not.toThrow();
  });

  it("作成者は削除できない", () => {
    expectReason(() => {
      assertCanRemove(room, "alice", "alice");
    }, "cannot-remove-owner");
  });
});

describe("作るドキュメント", () => {
  it("作成直後のルームは open で、メンバーは作成者 1 人（02 の F-02 の AC）", () => {
    const room = newRoomDoc(
      { name: "年末の旅行", postLimit: 3, unlockRule: "deadline", deadlineAtMs: 1000, likeMode: "equal" },
      alice,
      "DK729Q",
      "NOW",
      (ms) => `T${String(ms)}`,
    );
    expect(room).toEqual({
      name: "年末の旅行",
      ownerId: "alice",
      inviteCode: "DK729Q",
      status: "open",
      settings: { postLimit: 3, unlockRule: "deadline", deadlineAt: "T1000", likeMode: "equal" },
      forcedUnlock: false,
      memberIds: ["alice"],
      memberCount: 1,
      readyCount: 0,
      candidateCount: 0,
      adFreeSponsor: { uid: "alice", displayName: "ありす" },
      currentDrawId: null,
      winnerCandidateId: null,
      excludedCandidateIds: [],
      reroll: { used: false, votesFor: [], votesAgainst: [], status: "none" },
      createdAt: "NOW",
      drawnAt: null,
      closedAt: null,
    });
  });

  it("締切日時が無ければ null", () => {
    const room = newRoomDoc(
      { name: "a", postLimit: 3, unlockRule: "all", deadlineAtMs: null, likeMode: "boost" },
      bob,
      "DK729Q",
      "NOW",
      () => "never",
    );
    expect(room.settings.deadlineAt).toBeNull();
    expect(room.adFreeSponsor).toBeNull();
  });

  it("メンバーは準備OKが false から始まり、lastSeenAt は joinedAt と同じ値（02 の F-04）", () => {
    expect(newMemberDoc({ displayName: "ぼぶ", avatarColor: "#23775D" }, "member", "NOW")).toEqual({
      displayName: "ぼぶ",
      avatarColor: "#23775D",
      role: "member",
      ready: false,
      joinedAt: "NOW",
      lastSeenAt: "NOW",
    });
  });
});
