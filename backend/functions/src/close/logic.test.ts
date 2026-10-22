import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { AUTO_CLOSE_AFTER_DRAW_MS } from "../domain/constants";
import type { CandidateDoc, RoomStatus } from "../domain/models";
import { APP_ERRORS } from "../errors";
import {
  autoCloseCutoffMs,
  decideClose,
  isAutoCloseDue,
  pastIdeaId,
  planPastIdeas,
  rerollUpdateOnClose,
  roomClosedBy,
  type ClosedRoomSource,
} from "./logic";

/** 判定の時刻の基準 */
const NOW_MS = 1_793_070_000_000;

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

/** alice が作成者で、bob がメンバーのルーム */
function room(status: RoomStatus) {
  return { status, ownerId: "alice", memberIds: ["alice", "bob"] };
}

describe("decideClose（02 の §6.3「この行き先で決定」・F-44）", () => {
  it("作成者は drawn のルームを終了できる", () => {
    expect(decideClose(room("drawn"), "alice")).toBe("close");
  });

  it("もう closed なら何もしない（自動の終了と重なった・二度押し）", () => {
    expect(decideClose(room("closed"), "alice")).toBe("alreadyClosed");
  });

  it("作成者以外は not-room-owner（状態によらない）", () => {
    for (const status of ["open", "unlocked", "drawn", "closed"] as const) {
      expectReason(() => decideClose(room(status), "bob"), "not-room-owner");
    }
  });

  it("メンバーでなければ not-room-member（作成者の確認より先）", () => {
    expectReason(() => decideClose(room("drawn"), "carol"), "not-room-member");
    expectReason(() => decideClose({ status: "drawn", ownerId: "alice" }, "alice"), "not-room-member");
  });

  it("行き先が決まる前（open・unlocked。引き直しの可決で戻った unlocked を含む）は room-not-drawn", () => {
    expectReason(() => decideClose(room("open"), "alice"), "room-not-drawn");
    expectReason(() => decideClose(room("unlocked"), "alice"), "room-not-drawn");
  });

  it("room-not-drawn は failed-precondition で「まだ行き先が決まっていません」", () => {
    expect(APP_ERRORS["room-not-drawn"]).toEqual({ code: "failed-precondition", message: "まだ行き先が決まっていません" });
  });
});

describe("rerollUpdateOnClose（終了するときに引き直しの投票を締める）", () => {
  it("投票中なら否決にする（票と使ったことは変えない）", () => {
    const reroll = { used: true, status: "voting", votesFor: ["bob"], votesAgainst: ["alice"] };
    expect(rerollUpdateOnClose({ reroll })).toEqual({ "reroll.status": "rejected" });
  });

  it("投票中でなければ何も足さない（提案されていない・可決・否決・壊れたデータ）", () => {
    for (const status of ["none", "passed", "rejected", undefined]) {
      expect(rerollUpdateOnClose({ reroll: { status } })).toEqual({});
    }
    expect(rerollUpdateOnClose({})).toEqual({});
    expect(rerollUpdateOnClose({ reroll: null })).toEqual({});
  });
});

describe("isAutoCloseDue（02 の §6.5「抽選から7日経過で自動的に closed」・06 の §4 の仮決め 7 日）", () => {
  it("仮決めの 7 日", () => {
    expect(AUTO_CLOSE_AFTER_DRAW_MS).toBe(7 * 24 * 60 * 60 * 1000);
  });

  it("抽選からちょうど 7 日で終了する・1 ミリ秒前はまだ", () => {
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: NOW_MS - AUTO_CLOSE_AFTER_DRAW_MS }, NOW_MS)).toBe(true);
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: NOW_MS - AUTO_CLOSE_AFTER_DRAW_MS + 1 }, NOW_MS)).toBe(false);
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: NOW_MS - 8 * 24 * 60 * 60 * 1000 }, NOW_MS)).toBe(true);
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: NOW_MS }, NOW_MS)).toBe(false);
  });

  it("drawn 以外・抽選の日時が無いときは終了しない", () => {
    const old = NOW_MS - 30 * 24 * 60 * 60 * 1000;
    for (const status of ["open", "unlocked", "closed", undefined]) {
      expect(isAutoCloseDue({ status, drawnAtMs: old }, NOW_MS)).toBe(false);
    }
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: null }, NOW_MS)).toBe(false);
  });

  it("クエリの境目は今の 7 日前（境目ちょうどの抽選は終了の対象）", () => {
    const cutoff = autoCloseCutoffMs(NOW_MS);
    expect(cutoff).toBe(NOW_MS - AUTO_CLOSE_AFTER_DRAW_MS);
    expect(isAutoCloseDue({ status: "drawn", drawnAtMs: cutoff }, NOW_MS)).toBe(true);
  });
});

describe("roomClosedBy（onRoomClosed が過去のアイデアを登録するか）", () => {
  it("closed でなかったのが closed になったときだけ true", () => {
    expect(roomClosedBy({ status: "drawn" }, { status: "closed" })).toBe(true);
    expect(roomClosedBy(undefined, { status: "closed" })).toBe(true);
    expect(roomClosedBy({ status: "closed" }, { status: "closed" })).toBe(false);
    expect(roomClosedBy({ status: "unlocked" }, { status: "drawn" })).toBe(false);
    expect(roomClosedBy({ status: "drawn" }, undefined)).toBe(false);
  });
});

describe("planPastIdeas（02 の §6.5・§3.4 F-13）", () => {
  const closedAt = Timestamp.fromMillis(NOW_MS);

  /** 候補（`likedBy` の数がいいね数） */
  function candidate(name: string, likedBy: string[] = [], overrides: Partial<CandidateDoc> = {}): Partial<CandidateDoc> {
    return {
      place: { name, area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
      category: "aquarium",
      postedBy: "bob",
      likedBy,
      ...overrides,
    };
  }

  /** ルーム（c1 が当選、alice・bob がメンバー） */
  function source(overrides: Partial<ClosedRoomSource> = {}): ClosedRoomSource {
    return {
      roomId: "room1",
      name: "年末の旅行",
      winnerCandidateId: "c1",
      memberIds: ["alice", "bob"],
      closedAt,
      ...overrides,
    };
  }

  it("当選以外の候補を、各メンバーに登録する（自分以外の投稿も・引き直しで外れた前の当選も）", () => {
    const writes = planPastIdeas(source(), [
      { id: "c2", data: candidate("江の島", ["alice", "bob", "carol"], { category: "sea", postedBy: "alice" }) },
      { id: "c1", data: candidate("サンシャイン水族館", ["bob"]) },
      { id: "c3", data: candidate("明治神宮", [], { category: "shrine" }) },
    ]);
    expect(writes.map((write) => [write.uid, write.ideaId])).toEqual([
      ["alice", "room1_c2"],
      ["alice", "room1_c3"],
      ["bob", "room1_c2"],
      ["bob", "room1_c3"],
    ]);
    expect(writes[0]?.doc).toEqual({
      sourceRoomId: "room1",
      sourceRoomName: "年末の旅行",
      sourceClosedAt: closedAt,
      sourceWinnerName: "サンシャイン水族館",
      place: { name: "江の島", area: "東京・豊島区", latitude: 35.7, longitude: 139.7, mapItemId: null },
      category: "sea",
      prevLikeCount: 3,
    });
    expect(writes[1]?.doc.prevLikeCount).toBe(0);
  });

  it("候補が当選の 1 件だけなら何も登録しない", () => {
    expect(planPastIdeas(source(), [{ id: "c1", data: candidate("城ヶ島") }])).toEqual([]);
  });

  it("同じ uid が 2 回あっても 1 回だけ登録する・メンバーがいなければ登録しない", () => {
    const candidates = [
      { id: "c1", data: candidate("城ヶ島") },
      { id: "c2", data: candidate("江の島") },
    ];
    expect(planPastIdeas(source({ memberIds: ["alice", "alice"] }), candidates)).toHaveLength(1);
    expect(planPastIdeas(source({ memberIds: [] }), candidates)).toEqual([]);
  });

  it("場所が壊れた候補は飛ばし、知らないカテゴリは town・エリアが無ければ空にする", () => {
    const writes = planPastIdeas(source({ memberIds: ["alice"] }), [
      { id: "c1", data: candidate("城ヶ島") },
      { id: "c2", data: { category: "sea", likedBy: [] } },
      {
        id: "c3",
        data: { place: { name: "高尾山", latitude: 35.6, longitude: 139.2 } as never, category: "mountain" as never },
      },
    ]);
    expect(writes).toHaveLength(1);
    expect(writes[0]?.doc.category).toBe("town");
    expect(writes[0]?.doc.place).toEqual({ name: "高尾山", area: "", latitude: 35.6, longitude: 139.2, mapItemId: null });
    expect(writes[0]?.doc.prevLikeCount).toBe(0);
  });

  it("当選の候補が見つからなければ、当選の名前は空のまま、すべての候補を登録する", () => {
    const writes = planPastIdeas(source({ winnerCandidateId: null, memberIds: ["alice"] }), [
      { id: "c1", data: candidate("城ヶ島") },
      { id: "c2", data: candidate("江の島") },
    ]);
    expect(writes.map((write) => write.ideaId)).toEqual(["room1_c1", "room1_c2"]);
    expect(writes[0]?.doc.sourceWinnerName).toBe("");
  });

  it("同じ入力なら同じ ID と値（やり直しても重ねて作らない）", () => {
    const candidates = [
      { id: "c2", data: candidate("江の島") },
      { id: "c1", data: candidate("城ヶ島") },
    ];
    expect(planPastIdeas(source(), candidates)).toEqual(planPastIdeas(source(), [...candidates].reverse()));
    expect(pastIdeaId("room1", "c2")).toBe("room1_c2");
  });
});
