import { HttpsError } from "firebase-functions/v2/https";

import { assertCanInvite, lastMembersInvitees } from "./logic";

/** 投げたエラーの `details.reason` */
function reasonOf(run: () => void): unknown {
  try {
    run();
  } catch (error) {
    return error instanceof HttpsError ? (error.details as { reason?: unknown } | undefined)?.reason : error;
  }
  return null;
}

describe("前回のメンバーに招待できるか（02 の §2.4）", () => {
  test("今のルームのメンバーなら、作成者でなくても open・unlocked で招待できる", () => {
    expect(reasonOf(() => { assertCanInvite({ status: "open", memberIds: ["owner", "a"] }, "owner"); })).toBeNull();
    expect(reasonOf(() => { assertCanInvite({ status: "unlocked", memberIds: ["owner", "a"] }, "a"); })).toBeNull();
  });

  test("メンバーでなければ not-room-member（状態より先に確かめる）", () => {
    expect(reasonOf(() => { assertCanInvite({ status: "closed", memberIds: ["owner"] }, "x"); })).toBe("not-room-member");
    expect(reasonOf(() => { assertCanInvite({ status: "open" }, "x"); })).toBe("not-room-member");
  });

  test("行き先が決まったルーム（drawn・closed）には招待できない（参加できないため）", () => {
    expect(reasonOf(() => { assertCanInvite({ status: "drawn", memberIds: ["owner"] }, "owner"); })).toBe("room-already-decided");
    expect(reasonOf(() => { assertCanInvite({ status: "closed", memberIds: ["owner"] }, "owner"); })).toBe("room-already-decided");
  });
});

describe("招待する人（自分以外・今のルームにいる人を除く）", () => {
  test("前回のメンバーから自分と今のメンバーを外し、参加の順を保つ", () => {
    expect(lastMembersInvitees(["me", "a", "b", "c"], ["me", "b"], "me")).toEqual(["a", "c"]);
  });

  test("同じ人は 1 回だけ", () => {
    expect(lastMembersInvitees(["a", "me", "a", "b"], ["me"], "me")).toEqual(["a", "b"]);
  });

  test("前回が自分だけ・全員がもう今のルームにいるなら 0 人", () => {
    expect(lastMembersInvitees(["me"], ["me"], "me")).toEqual([]);
    expect(lastMembersInvitees(["me", "a"], ["me", "a"], "me")).toEqual([]);
  });
});
