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

  it("設定の変更（02 の F-03）の文言は、どれも今の状態では変えられない failed-precondition", () => {
    expect(APP_ERRORS["room-closed"]).toEqual({ code: "failed-precondition", message: "このルームは終了しています" });
    expect(APP_ERRORS["post-limit-decrease"]).toEqual({
      code: "failed-precondition",
      message: "投稿数は今より少なくできません",
    });
    expect(APP_ERRORS["unlock-rule-locked"]).toEqual({
      code: "failed-precondition",
      message: "解禁の条件は候補募集中のときだけ変更できます",
    });
    expect(APP_ERRORS["like-mode-locked"]).toEqual({
      code: "failed-precondition",
      message: "行き先が決まった後は、いいねの効き方を変更できません",
    });
  });

  it("抽選（02 の F-40「候補がありません」）と、当選した候補の削除の文言", () => {
    expect(APP_ERRORS["room-not-unlocked"]).toEqual({
      code: "failed-precondition",
      message: "まだガチャは解禁されていません",
    });
    expect(APP_ERRORS["no-candidates"]).toEqual({ code: "failed-precondition", message: "候補がありません" });
    expect(APP_ERRORS["candidate-drawn"]).toEqual({
      code: "failed-precondition",
      message: "ガチャで当選した候補は削除できません",
    });
  });

  it("引き直し（02 の §6.4「使用済み」の表示・F-43 の AC「2回目を提案できない」）の文言", () => {
    expect(APP_ERRORS["room-not-drawn"]).toEqual({ code: "failed-precondition", message: "まだ行き先が決まっていません" });
    expect(APP_ERRORS["reroll-used"]).toEqual({ code: "failed-precondition", message: "引き直しは使用済みです" });
    expect(APP_ERRORS["reroll-not-voting"]).toEqual({
      code: "failed-precondition",
      message: "引き直しの投票は終わっています",
    });
  });

  it("投稿の報告（02 の §3.5。自分の投稿は報告できない）の文言", () => {
    expect(APP_ERRORS["cannot-report-own-candidate"]).toEqual({
      code: "failed-precondition",
      message: "自分の投稿は報告できません",
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
