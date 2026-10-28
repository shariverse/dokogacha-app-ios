import { HttpsError } from "firebase-functions/v2/https";

import { requireAuth, runCallable } from "./callable";
import { appError } from "./errors";

describe("requireAuth", () => {
  it("サインインしていなければ unauthenticated", () => {
    let thrown: unknown;
    try {
      requireAuth({});
    } catch (error) {
      thrown = error;
    }
    expect(thrown).toMatchObject({ code: "unauthenticated", details: { reason: "unauthenticated" } });
  });

  it("サインインしていれば uid を返す", () => {
    expect(requireAuth({ auth: { uid: "alice", token: {} as never, rawToken: "" } })).toBe("alice");
  });
});

describe("runCallable", () => {
  const request = { auth: { uid: "alice", token: {} as never, rawToken: "" }, data: { a: 1 } };

  it("uid と data を渡して結果を返す", async () => {
    await expect(runCallable("test", request, (uid, data) => Promise.resolve({ uid, data }))).resolves.toEqual({
      uid: "alice",
      data: { a: 1 },
    });
  });

  it("サインインしていなければ処理を呼ばない", async () => {
    const handler = jest.fn(() => Promise.resolve(1));
    await expect(runCallable("test", { data: {} }, handler)).rejects.toBeInstanceOf(HttpsError);
    expect(handler).not.toHaveBeenCalled();
  });

  it("HttpsError はそのまま返す", async () => {
    await expect(runCallable("test", request, () => Promise.reject(appError("room-full")))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "room-full" },
    });
  });

  it("想定していない例外は internal にする", async () => {
    await expect(
      runCallable("test", request, () => Promise.reject(new Error("内部の情報"))),
    ).rejects.toMatchObject({ code: "internal", message: "通信できませんでした", details: { reason: "internal" } });
  });
});
