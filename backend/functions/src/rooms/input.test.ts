import {
  DEADLINE_EARLIEST_GRACE_MS,
  parseCreateRoomInput,
  parseJoinRoomInput,
  parseLeaveRoomInput,
  parseRemoveMemberInput,
} from "./input";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
/** サーバーの今（2026-10-22 12:00 UTC） */
const NOW = Date.UTC(2026, 9, 22, 12, 0);

/** 関数が指定した理由の HttpsError を投げることを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  expect(run).toThrow(expect.objectContaining({ details: { reason } }) as Error);
}

const valid = { name: "年末の旅行", postLimit: 3, unlockRule: "all", likeMode: "boost" };

describe("parseCreateRoomInput（02 の F-02）", () => {
  it("正しい入力を受け付け、ルーム名の前後の空白を取り除く", () => {
    expect(parseCreateRoomInput({ ...valid, name: " 年末の旅行 " }, NOW)).toEqual({
      name: "年末の旅行",
      postLimit: 3,
      unlockRule: "all",
      deadlineAtMs: null,
      likeMode: "boost",
    });
  });

  it("ルーム名は 1〜20 文字（空は受け付けない）", () => {
    expect(parseCreateRoomInput({ ...valid, name: "あ".repeat(20) }, NOW).name).toHaveLength(20);
    // 1 文字でも UTF-16 で 320 を超える長さ（結合文字をつないだ 1 文字）は受け付けない
    const longest = `あ${"\u{3099}".repeat(319)}`;
    expect(parseCreateRoomInput({ ...valid, name: longest }, NOW).name).toBe(longest);
    for (const name of ["", "　", "あ".repeat(21), `${longest}\u{3099}`, undefined, 1]) {
      expectReason(() => parseCreateRoomInput({ ...valid, name }, NOW), "invalid-argument");
    }
  });

  it("投稿数は 1〜10 の整数（1 未満・10 超にできない）", () => {
    expect(parseCreateRoomInput({ ...valid, postLimit: 1 }, NOW).postLimit).toBe(1);
    expect(parseCreateRoomInput({ ...valid, postLimit: 10 }, NOW).postLimit).toBe(10);
    for (const postLimit of [0, 11, 2.5, "3", undefined]) {
      expectReason(() => parseCreateRoomInput({ ...valid, postLimit }, NOW), "invalid-argument");
    }
  });

  it("解禁の条件といいねの効き方は決まった値だけ", () => {
    expect(parseCreateRoomInput({ ...valid, unlockRule: "majority", likeMode: "equal" }, NOW)).toMatchObject({
      unlockRule: "majority",
      likeMode: "equal",
    });
    expectReason(() => parseCreateRoomInput({ ...valid, unlockRule: "force" }, NOW), "invalid-argument");
    expectReason(() => parseCreateRoomInput({ ...valid, likeMode: "BOOST" }, NOW), "invalid-argument");
  });

  it("締切日時は deadline のときだけ必須で、今から 1 時間後（猶予つき）〜30 日後", () => {
    const deadline = { ...valid, unlockRule: "deadline" };
    expect(parseCreateRoomInput({ ...deadline, deadlineAt: NOW + HOUR }, NOW).deadlineAtMs).toBe(NOW + HOUR);
    expect(parseCreateRoomInput({ ...deadline, deadlineAt: NOW + 30 * DAY }, NOW).deadlineAtMs).toBe(NOW + 30 * DAY);
    expect(
      parseCreateRoomInput({ ...deadline, deadlineAt: NOW + HOUR - DEADLINE_EARLIEST_GRACE_MS }, NOW).deadlineAtMs,
    ).toBe(NOW + HOUR - DEADLINE_EARLIEST_GRACE_MS);
    for (const deadlineAt of [undefined, null, NOW + HOUR - DEADLINE_EARLIEST_GRACE_MS - 1, NOW + 30 * DAY + 1, "x"]) {
      expectReason(() => parseCreateRoomInput({ ...deadline, deadlineAt }, NOW), "invalid-argument");
    }
  });

  it("deadline 以外の条件では締切日時を送らない（null は可）", () => {
    expect(parseCreateRoomInput({ ...valid, deadlineAt: null }, NOW).deadlineAtMs).toBeNull();
    expectReason(() => parseCreateRoomInput({ ...valid, deadlineAt: NOW + DAY }, NOW), "invalid-argument");
  });

  it("オブジェクトでなければ受け付けない", () => {
    expectReason(() => parseCreateRoomInput(null, NOW), "invalid-argument");
  });
});

describe("parseJoinRoomInput（02 の F-04）", () => {
  it("招待コードをサーバーでも正規化する（小文字・ハイフン・全角・空白）", () => {
    expect(parseJoinRoomInput({ inviteCode: "dk7-29q" })).toEqual({ inviteCode: "DK729Q" });
    expect(parseJoinRoomInput({ inviteCode: "ＤＫ７－２９Ｑ" })).toEqual({ inviteCode: "DK729Q" });
    expect(parseJoinRoomInput({ inviteCode: "\u{FEFF}DK7\u{0085}29Q" })).toEqual({ inviteCode: "DK729Q" });
  });

  it("招待コードの形でなければ「招待コードが見つかりません」", () => {
    for (const inviteCode of ["", "DK729", "DK729O", "../x"]) {
      expectReason(() => parseJoinRoomInput({ inviteCode }), "invite-code-not-found");
    }
  });

  it("文字列でなければ invalid-argument", () => {
    expectReason(() => parseJoinRoomInput({ inviteCode: 123 }), "invalid-argument");
    expectReason(() => parseJoinRoomInput({}), "invalid-argument");
  });
});

describe("parseLeaveRoomInput・parseRemoveMemberInput", () => {
  it("ID を検証する", () => {
    expect(parseLeaveRoomInput({ roomId: "room1" })).toEqual({ roomId: "room1" });
    expect(parseRemoveMemberInput({ roomId: "room1", memberId: "bob" })).toEqual({ roomId: "room1", memberId: "bob" });
    expectReason(() => parseLeaveRoomInput({ roomId: "rooms/room1" }), "invalid-argument");
    expectReason(() => parseRemoveMemberInput({ roomId: "room1" }), "invalid-argument");
  });
});
