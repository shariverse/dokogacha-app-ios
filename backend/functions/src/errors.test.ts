import { HttpsError } from "firebase-functions/v2/https";

import { APP_ERRORS, appError } from "./errors";

describe("APP_ERRORS", () => {
  it("02 の F-04 の AC の文言どおり", () => {
    expect(APP_ERRORS["invite-code-not-found"].message).toBe("招待コードが見つかりません");
    expect(APP_ERRORS["room-full"].message).toBe("このルームは満員です（最大20人）");
    expect(APP_ERRORS["room-already-decided"].message).toBe("このルームはもう行き先が決まっています");
  });

  it("想定していないエラーとサインインの無いときは「通信できませんでした」（05 の §6 のトースト）", () => {
    expect(APP_ERRORS.internal.message).toBe("通信できませんでした");
    expect(APP_ERRORS.unauthenticated).toEqual({ code: "unauthenticated", message: "通信できませんでした" });
  });
});

describe("appError", () => {
  it("コード・文言・理由を持つ HttpsError を作る", () => {
    const error = appError("room-full");
    expect(error).toBeInstanceOf(HttpsError);
    expect(error.code).toBe("resource-exhausted");
    expect(error.message).toBe("このルームは満員です（最大20人）");
    expect(error.details).toEqual({ reason: "room-full" });
  });

  it("どの理由も、アプリに返せる形（JSON）になる", () => {
    for (const reason of Object.keys(APP_ERRORS) as (keyof typeof APP_ERRORS)[]) {
      const json = appError(reason).toJSON();
      expect(json).toEqual({ status: expect.any(String) as unknown, message: APP_ERRORS[reason].message, details: { reason } });
    }
  });
});
