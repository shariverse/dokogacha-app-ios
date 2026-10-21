import { chunk, countRoomCopyWrites, planRoomCopyUpdates, profileCopyChanged, type RoomCopies } from "./logic";

const profile = { displayName: "ありす", avatarColor: "#F4A6A6" };

/** 自分（alice）が参加していて、複製が古い名前のルーム */
function staleRoom(overrides: Partial<RoomCopies> = {}): RoomCopies {
  return {
    memberIds: ["alice", "bob"],
    adFreeSponsor: null,
    member: { displayName: "alice", avatarColor: "#F4A6A6" },
    candidates: [
      { id: "c1", postedByName: "alice" },
      { id: "c2", postedByName: "alice" },
    ],
    ...overrides,
  };
}

describe("profileCopyChanged", () => {
  it("表示名かアバターの色が変わったときだけ true", () => {
    expect(profileCopyChanged({ displayName: "a", avatarColor: "#1" }, { displayName: "b", avatarColor: "#1" })).toBe(true);
    expect(profileCopyChanged({ displayName: "a", avatarColor: "#1" }, { displayName: "a", avatarColor: "#2" })).toBe(true);
    expect(profileCopyChanged({ displayName: "a", avatarColor: "#1" }, { displayName: "a", avatarColor: "#1" })).toBe(false);
  });

  it("消えたプロフィールでは反映しない", () => {
    expect(profileCopyChanged({ displayName: "a", avatarColor: "#1" }, undefined)).toBe(false);
  });
});

describe("planRoomCopyUpdates", () => {
  it("メンバーの表示名と、自分の候補の投稿者名を今の名前にする", () => {
    const updates = planRoomCopyUpdates("alice", profile, staleRoom());
    expect(updates).toEqual({ member: { displayName: "ありす" }, sponsor: null, candidateIds: ["c1", "c2"] });
    expect(countRoomCopyWrites(updates)).toBe(3);
  });

  it("アバターの色が違えば色も書く", () => {
    const updates = planRoomCopyUpdates("alice", profile, staleRoom({ member: { displayName: "ありす", avatarColor: "#000000" } }));
    expect(updates.member).toEqual({ avatarColor: "#F4A6A6" });
  });

  it("自分が広告非表示の購入者なら、購入者の表示名も書く。ほかの人が購入者なら書かない", () => {
    expect(planRoomCopyUpdates("alice", profile, staleRoom({ adFreeSponsor: { uid: "alice", displayName: "alice" } })).sponsor).toEqual(
      { uid: "alice", displayName: "ありす" },
    );
    expect(planRoomCopyUpdates("alice", profile, staleRoom({ adFreeSponsor: { uid: "bob", displayName: "bob" } })).sponsor).toBeNull();
  });

  it("すでに今の値なら何も書かない（冪等）", () => {
    const current = staleRoom({
      adFreeSponsor: { uid: "alice", displayName: "ありす" },
      member: { ...profile },
      candidates: [{ id: "c1", postedByName: "ありす" }],
    });
    const updates = planRoomCopyUpdates("alice", profile, current);
    expect(updates).toEqual({ member: null, sponsor: null, candidateIds: [] });
    expect(countRoomCopyWrites(updates)).toBe(0);
  });

  it("一部だけ古いときは、古いものだけを書く", () => {
    const updates = planRoomCopyUpdates(
      "alice",
      profile,
      staleRoom({ member: { ...profile }, candidates: [{ id: "c1", postedByName: "ありす" }, { id: "c2", postedByName: "alice" }] }),
    );
    expect(updates).toEqual({ member: null, sponsor: null, candidateIds: ["c2"] });
  });

  it("もうメンバーでないルーム（退出・削除の後）には書かない", () => {
    expect(planRoomCopyUpdates("alice", profile, staleRoom({ memberIds: ["bob"] }))).toEqual({
      member: null,
      sponsor: null,
      candidateIds: [],
    });
    expect(planRoomCopyUpdates("alice", profile, staleRoom({ member: undefined }))).toEqual({
      member: null,
      sponsor: null,
      candidateIds: [],
    });
  });
});

describe("chunk", () => {
  it("元の順を保って size 件ずつに分ける", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([1, 2], 2)).toEqual([[1, 2]]);
    expect(chunk([], 3)).toEqual([]);
  });

  it.each([0, -1, 1.5])("size が %p なら投げる", (size) => {
    expect(() => chunk([1], size)).toThrow(RangeError);
  });
});
