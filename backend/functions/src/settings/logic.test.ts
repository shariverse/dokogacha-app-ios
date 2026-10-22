import { HttpsError } from "firebase-functions/v2/https";

import type { RoomStatus } from "../domain/models";
import type { UpdateRoomSettingsInput } from "./input";
import { planSettingsUpdate, type CurrentRoomSettings } from "./logic";

/** 判定の時刻の基準 */
const NOW_MS = 1_793_070_000_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

/** 今のルーム（指定しない値は「open・alice が作成者・投稿数 3・全員OK・共感ブースト」） */
function room(overrides: Partial<CurrentRoomSettings> = {}): CurrentRoomSettings {
  return {
    status: "open",
    ownerId: "alice",
    name: "年末の旅行",
    postLimit: 3,
    unlockRule: "all",
    deadlineAtMs: null,
    likeMode: "boost",
    ...overrides,
  };
}

/** 入力（roomId 付き） */
function input(values: Omit<UpdateRoomSettingsInput, "roomId">): UpdateRoomSettingsInput {
  return { roomId: "room1", ...values };
}

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

describe("planSettingsUpdate（02 の F-03）", () => {
  it("作成者以外は変えられない（今と同じ値でも）", () => {
    expectReason(() => planSettingsUpdate(room(), "bob", input({ name: "春" }), NOW_MS), "not-room-owner");
    expectReason(() => planSettingsUpdate(room(), "bob", input({}), NOW_MS), "not-room-owner");
  });

  it("closed のルームは何も変えられない（ルーム名も）", () => {
    expectReason(
      () => planSettingsUpdate(room({ status: "closed" }), "alice", input({ name: "春" }), NOW_MS),
      "room-closed",
    );
  });

  it.each<RoomStatus>(["open", "unlocked", "drawn"])("ルーム名は %s でも変えられる（closed 以外）", (status) => {
    expect(planSettingsUpdate(room({ status }), "alice", input({ name: "春の旅行" }), NOW_MS)).toEqual({ name: "春の旅行" });
  });

  describe("投稿数（引き上げのみ）", () => {
    it.each<RoomStatus>(["open", "unlocked", "drawn"])("%s で引き上げられる", (status) => {
      expect(planSettingsUpdate(room({ status }), "alice", input({ postLimit: 5 }), NOW_MS)).toEqual({ postLimit: 5 });
    });

    it("下げられない", () => {
      expectReason(() => planSettingsUpdate(room(), "alice", input({ postLimit: 2 }), NOW_MS), "post-limit-decrease");
    });

    it("今と同じ値は変えない", () => {
      expect(planSettingsUpdate(room(), "alice", input({ postLimit: 3 }), NOW_MS)).toEqual({});
    });
  });

  describe("解禁の条件（open のときのみ）", () => {
    it("open で全員OK → 過半数OK にできる（締切日時は null のまま）", () => {
      expect(planSettingsUpdate(room(), "alice", input({ unlockRule: "majority" }), NOW_MS)).toEqual({
        unlockRule: "majority",
        deadlineAtMs: null,
      });
    });

    it("締切日時にするには締切日時が要り、範囲は今から 1 時間後（5 分の猶予）〜30 日後", () => {
      const deadline = NOW_MS + 2 * HOUR_MS;
      expect(planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline", deadlineAtMs: deadline }), NOW_MS)).toEqual({
        unlockRule: "deadline",
        deadlineAtMs: deadline,
      });
      expectReason(() => planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline" }), NOW_MS), "invalid-argument");
      // 猶予の境目（55 分後は通り、54 分 59.999 秒後は断る）と 30 日後の境目
      const earliest = NOW_MS + HOUR_MS - 5 * 60_000;
      expect(planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline", deadlineAtMs: earliest }), NOW_MS)).toEqual({
        unlockRule: "deadline",
        deadlineAtMs: earliest,
      });
      expectReason(
        () => planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline", deadlineAtMs: earliest - 1 }), NOW_MS),
        "invalid-argument",
      );
      expect(
        planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline", deadlineAtMs: NOW_MS + 30 * DAY_MS }), NOW_MS),
      ).toEqual({ unlockRule: "deadline", deadlineAtMs: NOW_MS + 30 * DAY_MS });
      expectReason(
        () =>
          planSettingsUpdate(room(), "alice", input({ unlockRule: "deadline", deadlineAtMs: NOW_MS + 30 * DAY_MS + 1 }), NOW_MS),
        "invalid-argument",
      );
    });

    it("締切日時から別の条件にすると締切日時を消す", () => {
      const current = room({ unlockRule: "deadline", deadlineAtMs: NOW_MS + DAY_MS });
      expect(planSettingsUpdate(current, "alice", input({ unlockRule: "all" }), NOW_MS)).toEqual({
        unlockRule: "all",
        deadlineAtMs: null,
      });
    });

    it("締切日時のままなら、締切日時だけを変えられる（条件は送らなくてよい）", () => {
      const current = room({ unlockRule: "deadline", deadlineAtMs: NOW_MS + DAY_MS });
      expect(planSettingsUpdate(current, "alice", input({ deadlineAtMs: NOW_MS + 2 * DAY_MS }), NOW_MS)).toEqual({
        deadlineAtMs: NOW_MS + 2 * DAY_MS,
      });
    });

    it("今の締切日時を送り直しても、範囲を過ぎていても断らない（変えていない）", () => {
      // 作成から時間が経ち、今の締切日時が「今から 1 時間後」より前になっている
      const current = room({ unlockRule: "deadline", deadlineAtMs: NOW_MS + 10 * 60_000 });
      expect(
        planSettingsUpdate(current, "alice", input({ unlockRule: "deadline", deadlineAtMs: NOW_MS + 10 * 60_000 }), NOW_MS),
      ).toEqual({});
    });

    it("今の条件が締切日時でないのに、締切日時だけを送ったら invalid-argument", () => {
      expectReason(
        () => planSettingsUpdate(room(), "alice", input({ deadlineAtMs: NOW_MS + DAY_MS }), NOW_MS),
        "invalid-argument",
      );
    });

    it.each<RoomStatus>(["unlocked", "drawn"])("%s では条件も締切日時も変えられない", (status) => {
      expectReason(
        () => planSettingsUpdate(room({ status }), "alice", input({ unlockRule: "majority" }), NOW_MS),
        "unlock-rule-locked",
      );
      const deadlineRoom = room({ status, unlockRule: "deadline", deadlineAtMs: NOW_MS + DAY_MS });
      expectReason(
        () => planSettingsUpdate(deadlineRoom, "alice", input({ deadlineAtMs: NOW_MS + 2 * DAY_MS }), NOW_MS),
        "unlock-rule-locked",
      );
    });

    it("unlocked でも、今と同じ条件を送っただけなら断らない（S-12 が全項目を送るとき）", () => {
      expect(planSettingsUpdate(room({ status: "unlocked" }), "alice", input({ unlockRule: "all", name: "春" }), NOW_MS)).toEqual(
        { name: "春" },
      );
    });
  });

  describe("いいねの効き方（open/unlocked のときのみ）", () => {
    it.each<RoomStatus>(["open", "unlocked"])("%s で変えられる", (status) => {
      expect(planSettingsUpdate(room({ status }), "alice", input({ likeMode: "equal" }), NOW_MS)).toEqual({ likeMode: "equal" });
    });

    it("drawn では変えられない（今と同じ値なら断らない）", () => {
      expectReason(
        () => planSettingsUpdate(room({ status: "drawn" }), "alice", input({ likeMode: "equal" }), NOW_MS),
        "like-mode-locked",
      );
      expect(planSettingsUpdate(room({ status: "drawn" }), "alice", input({ likeMode: "boost" }), NOW_MS)).toEqual({});
    });
  });

  it("すべての項目を一度に変えられる（open）", () => {
    expect(
      planSettingsUpdate(
        room(),
        "alice",
        input({ name: "春", postLimit: 10, unlockRule: "deadline", deadlineAtMs: NOW_MS + DAY_MS, likeMode: "equal" }),
        NOW_MS,
      ),
    ).toEqual({ name: "春", postLimit: 10, unlockRule: "deadline", deadlineAtMs: NOW_MS + DAY_MS, likeMode: "equal" });
  });

  it("確かめる順は表の順（投稿数を下げ、条件も変えようとしたら投稿数の理由）", () => {
    expectReason(
      () => planSettingsUpdate(room({ status: "drawn" }), "alice", input({ postLimit: 1, unlockRule: "majority" }), NOW_MS),
      "post-limit-decrease",
    );
  });
});
