import { HttpsError } from "firebase-functions/v2/https";

import { APP_ERRORS, appError } from "./errors";

describe("APP_ERRORS", () => {
  it("02 の F-04 の AC の文言どおり", () => {
    expect(APP_ERRORS["invite-code-not-found"].message).toBe("招待コードが見つかりません");
    expect(APP_ERRORS["room-full"].message).toBe("このルームは満員です（最大20人）");
    expect(APP_ERRORS["room-already-decided"].message).toBe("このルームはもう行き先が決まっています");
  });

  it("候補の追加・削除の文言（02 の §9 の 200 件・F-11 の投稿者か作成者）", () => {
    expect(APP_ERRORS["post-limit-reached"]).toEqual({ code: "resource-exhausted", message: "投稿できる数の上限に達しています" });
    expect(APP_ERRORS["room-candidates-full"].message).toBe("このルームの候補は上限に達しています（最大200件）");
    expect(APP_ERRORS["candidate-not-found"]).toEqual({ code: "not-found", message: "候補が見つかりません" });
    expect(APP_ERRORS["not-candidate-owner"]).toEqual({
      code: "permission-denied",
      message: "投稿した人と作成者だけが削除できます",
    });
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
