import type { ExistingCandidate } from "../domain/candidate";
import type { RoomStatus } from "../domain/models";
import type { AddCandidateInput } from "./input";
import { assertCanDeleteCandidate, decideAddCandidate, newCandidateDoc } from "./logic";

/** 理由つきの HttpsError を投げることを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  expect(run).toThrow(expect.objectContaining({ details: { reason } }) as Error);
}

const place: AddCandidateInput["place"] = {
  name: "江の島",
  area: "神奈川・藤沢市",
  latitude: 35.3,
  longitude: 139.48,
  mapItemId: null,
};

/** 投稿数の上限が `postLimit` のルーム */
function room(status: RoomStatus = "open", postLimit = 3) {
  return { status, ownerId: "alice", settings: { postLimit, unlockRule: "all", likeMode: "boost" } as const };
}

/** `postedBy` の、場所の違う候補を `count` 件 */
function others(postedBy: string, count: number, startIndex = 0): ExistingCandidate[] {
  return Array.from({ length: count }, (_, offset) => ({
    id: `${postedBy}-${String(offset)}`,
    place: { name: `場所${postedBy}${String(offset)}`, latitude: 35, longitude: 139 },
    postedBy,
    colorIndex: startIndex + offset,
    createdAtMs: offset,
  }));
}

describe("decideAddCandidate（02 の F-10）", () => {
  it("open・unlocked なら追加できる。colorIndex は既存の最大 + 1（最初は 0）", () => {
    expect(decideAddCandidate(room(), "bob", place, [])).toEqual({ kind: "add", colorIndex: 0 });
    expect(decideAddCandidate(room("unlocked"), "bob", place, others("alice", 2, 4))).toEqual({ kind: "add", colorIndex: 6 });
  });

  it("drawn・closed では追加できない（「このルームはもう行き先が決まっています」）", () => {
    for (const status of ["drawn", "closed"] as const) {
      expectReason(() => decideAddCandidate(room(status), "bob", place, []), "room-already-decided");
    }
  });

  it("同じ場所があれば作らずに既存の候補を返す（自分の投稿でも）", () => {
    const existing: ExistingCandidate[] = [
      ...others("alice", 1),
      { id: "mine", place: { ...place, latitude: 35.3005 }, postedBy: "bob", colorIndex: 1, createdAtMs: 10 },
    ];
    expect(decideAddCandidate(room(), "bob", place, existing)).toEqual({ kind: "duplicate", candidateId: "mine" });
  });

  it("自分の投稿数が上限に達していたら post-limit-reached（ほかの人の投稿は数えない）", () => {
    expect(decideAddCandidate(room("open", 2), "bob", place, [...others("bob", 1), ...others("alice", 5, 1)])).toEqual({
      kind: "add",
      colorIndex: 6,
    });
    expectReason(() => decideAddCandidate(room("open", 2), "bob", place, others("bob", 2)), "post-limit-reached");
  });

  it("上限に達していても、同じ場所なら重複を先に返す", () => {
    const existing: ExistingCandidate[] = [
      { id: "same", place, postedBy: "alice", colorIndex: 0, createdAtMs: 0 },
      ...others("bob", 3, 1),
    ];
    expect(decideAddCandidate(room("open", 3), "bob", place, existing)).toEqual({ kind: "duplicate", candidateId: "same" });
  });

  it("ルームの候補が 200 件なら room-candidates-full（退出した人の候補が残ったとき）", () => {
    const existing = Array.from({ length: 20 }, (_, index) => others(`u${String(index)}`, 10, index * 10)).flat();
    expect(existing).toHaveLength(200);
    expectReason(() => decideAddCandidate(room("open", 10), "newcomer", place, existing), "room-candidates-full");
    expect(decideAddCandidate(room("open", 10), "newcomer", place, existing.slice(1))).toEqual({
      kind: "add",
      colorIndex: 200,
    });
  });

  it("状態の確認がいちばん先（drawn なら重複でも上限でも room-already-decided）", () => {
    expectReason(
      () => decideAddCandidate(room("drawn", 1), "bob", place, [{ id: "same", place, postedBy: "bob", colorIndex: 0, createdAtMs: 0 }]),
      "room-already-decided",
    );
  });
});

describe("assertCanDeleteCandidate（02 の F-11）", () => {
  it("投稿した人と作成者は open・unlocked で削除できる", () => {
    for (const status of ["open", "unlocked"] as const) {
      expect(() => { assertCanDeleteCandidate(room(status), "bob", { postedBy: "bob" }); }).not.toThrow();
      expect(() => { assertCanDeleteCandidate(room(status), "alice", { postedBy: "bob" }); }).not.toThrow();
    }
  });

  it("投稿した人でも作成者でもなければ not-candidate-owner", () => {
    expectReason(() => { assertCanDeleteCandidate(room(), "carol", { postedBy: "bob" }); }, "not-candidate-owner");
  });

  it("drawn・closed では、投稿した人も作成者も削除できない", () => {
    for (const status of ["drawn", "closed"] as const) {
      expectReason(() => { assertCanDeleteCandidate(room(status), "bob", { postedBy: "bob" }); }, "room-already-decided");
      expectReason(() => { assertCanDeleteCandidate(room(status), "alice", { postedBy: "bob" }); }, "room-already-decided");
    }
  });
});

describe("newCandidateDoc", () => {
  it("いいねは 0 から・投稿した人の表示名を写す", () => {
    const input: AddCandidateInput = {
      roomId: "room1",
      place,
      category: "sea",
      note: "海！",
      url: null,
      fromPastIdeaId: "idea1",
    };
    expect(newCandidateDoc(input, { uid: "bob", displayName: "ぼぶ" }, 3, "now")).toEqual({
      place,
      category: "sea",
      note: "海！",
      url: null,
      postedBy: "bob",
      postedByName: "ぼぶ",
      colorIndex: 3,
      likedBy: [],
      fromPastIdeaId: "idea1",
      createdAt: "now",
    });
  });
});
