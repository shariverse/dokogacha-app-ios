import { digestSchedule, digestWindow, planDigests, type DigestRoom } from "./logic";

/** JST の日時（`2026-10-22T20:00` の形）を UNIX 時刻のミリ秒にする */
function jst(local: string): number {
  return Date.parse(`${local}:00+09:00`);
}

describe("まとめ通知のスケジュール（06 の §4 の仮決め 20:00 JST）", () => {
  test("毎日 20:00", () => {
    expect(digestSchedule()).toBe("every day 20:00");
  });
});

describe("まとめる範囲（前の日の 20:00〜今日の 20:00 JST）", () => {
  test("20:00 ちょうどに動いたら、その日の 20:00 までの 24 時間", () => {
    expect(digestWindow(jst("2026-10-22T20:00"))).toEqual({
      dateKey: "2026-10-22",
      startMs: jst("2026-10-21T20:00"),
      endMs: jst("2026-10-22T20:00"),
    });
  });

  test("遅れて動いても（やり直しでも）同じ範囲と同じ日", () => {
    expect(digestWindow(jst("2026-10-22T23:59"))).toEqual(digestWindow(jst("2026-10-22T20:00")));
  });

  test("20:00 より前なら、前の日の範囲（JST の 0 時をまたいでも日付は JST）", () => {
    expect(digestWindow(jst("2026-10-23T08:30")).dateKey).toBe("2026-10-22");
    expect(digestWindow(jst("2026-10-22T19:59")).dateKey).toBe("2026-10-21");
    // UTC ではまだ 10/22 の 11:00 だが、JST では 10/22 の 20:00
    expect(digestWindow(Date.parse("2026-10-22T11:00:00Z")).dateKey).toBe("2026-10-22");
  });
});

describe("送るルーム・N・送らない人（02 の §8）", () => {
  const rooms = new Map<string, DigestRoom>([
    ["r-open", { name: "年末の旅行", status: "open" }],
    ["r-unlocked", { name: "週末のランチ", status: "unlocked" }],
    ["r-drawn", { name: "春のお花見", status: "drawn" }],
    ["r-closed", { name: "夏の日帰り", status: "closed" }],
  ]);

  test("ルームごとに数え、2 人以上の投稿なら全メンバーに送る", () => {
    const events = planDigests(
      [
        { roomId: "r-open", postedBy: "a" },
        { roomId: "r-open", postedBy: "b" },
        { roomId: "r-open", postedBy: "a" },
      ],
      rooms,
      "2026-10-22",
    );
    expect(events).toEqual([
      { kind: "newCandidates", roomId: "r-open", roomName: "年末の旅行", dateKey: "2026-10-22", count: 3, onlyPosterId: null },
    ]);
  });

  test("増えた候補がすべて 1 人の投稿なら、その人には送らない", () => {
    const events = planDigests([{ roomId: "r-unlocked", postedBy: "a" }, { roomId: "r-unlocked", postedBy: "a" }], rooms, "d");
    expect(events.map((event) => [event.roomId, event.count, event.onlyPosterId])).toEqual([["r-unlocked", 2, "a"]]);
  });

  test("行き先が決まったルーム・無いルームには送らない。候補が無いルームも出ない", () => {
    const events = planDigests(
      [
        { roomId: "r-drawn", postedBy: "a" },
        { roomId: "r-closed", postedBy: "a" },
        { roomId: "r-missing", postedBy: "a" },
      ],
      rooms,
      "d",
    );
    expect(events).toEqual([]);
  });
});
