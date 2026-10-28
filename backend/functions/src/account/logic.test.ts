import type { RoomStatus } from "../domain/models";
import { accountDeletionActionOf, isAuthUserNotFound } from "./logic";

/** alice が作成者で、bob がメンバーのルーム */
function room(status: RoomStatus) {
  return { status, ownerId: "alice", memberIds: ["alice", "bob"] };
}

describe("accountDeletionActionOf（02 の F-06）", () => {
  it("作成者は、終了していないルーム（open・unlocked・drawn）を終了して外れる", () => {
    for (const status of ["open", "unlocked", "drawn"] as const) {
      expect(accountDeletionActionOf(room(status), "alice")).toBe("closeAndLeave");
    }
  });

  it("作成者でも、終了したルームは退出と同じに外れる（終了し直さない）", () => {
    expect(accountDeletionActionOf(room("closed"), "alice")).toBe("leave");
  });

  it("作成者でないメンバーは、どの状態のルームでも退出と同じに外れる", () => {
    for (const status of ["open", "unlocked", "drawn", "closed"] as const) {
      expect(accountDeletionActionOf(room(status), "bob")).toBe("leave");
    }
  });

  it("もうメンバーでない（前の呼び出しで外し終えた）ルームでは何もしない", () => {
    expect(accountDeletionActionOf(room("open"), "carol")).toBe("none");
    // 作成者の ID が残っていても、メンバーにいなければ何もしない（終了して外し終えたルーム）
    expect(accountDeletionActionOf({ status: "closed", ownerId: "alice", memberIds: ["bob"] }, "alice")).toBe("none");
  });

  it("memberIds が壊れていれば何もしない", () => {
    expect(accountDeletionActionOf({ status: "open", ownerId: "alice" }, "alice")).toBe("none");
    expect(accountDeletionActionOf({ status: "open", ownerId: "alice", memberIds: "alice" }, "alice")).toBe("none");
  });
});

describe("isAuthUserNotFound", () => {
  it("Admin SDK の auth/user-not-found だけを「もういない」とみなす", () => {
    expect(isAuthUserNotFound({ code: "auth/user-not-found", message: "no user" })).toBe(true);
    expect(isAuthUserNotFound({ code: "auth/internal-error" })).toBe(false);
    expect(isAuthUserNotFound(new Error("auth/user-not-found"))).toBe(false);
    expect(isAuthUserNotFound(null)).toBe(false);
    expect(isAuthUserNotFound("auth/user-not-found")).toBe(false);
  });
});
