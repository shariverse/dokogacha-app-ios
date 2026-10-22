import { parseUpdateRoomSettingsInput } from "./input";

/** invalid-argument で失敗することを確かめる */
function expectInvalid(data: unknown): void {
  expect(() => parseUpdateRoomSettingsInput(data)).toThrow(
    expect.objectContaining({ details: { reason: "invalid-argument" } }) as Error,
  );
}

describe("parseUpdateRoomSettingsInput", () => {
  it("送った項目だけを返す（鍵が無い・null は変えない）", () => {
    expect(parseUpdateRoomSettingsInput({ roomId: "room1" })).toEqual({ roomId: "room1" });
    expect(
      parseUpdateRoomSettingsInput({ roomId: "room1", name: null, postLimit: null, unlockRule: null, deadlineAt: null, likeMode: null }),
    ).toEqual({ roomId: "room1" });
    expect(
      parseUpdateRoomSettingsInput({
        roomId: "room1",
        name: " 春の旅行 ",
        postLimit: 5,
        unlockRule: "deadline",
        deadlineAt: 1_800_000_000_000,
        likeMode: "equal",
      }),
    ).toEqual({
      roomId: "room1",
      name: "春の旅行",
      postLimit: 5,
      unlockRule: "deadline",
      deadlineAtMs: 1_800_000_000_000,
      likeMode: "equal",
    });
  });

  it("条件を送らずに締切日時だけを送れる（今の条件が締切日時かは logic.ts で確かめる）", () => {
    expect(parseUpdateRoomSettingsInput({ roomId: "room1", deadlineAt: 1_800_000_000_000 })).toEqual({
      roomId: "room1",
      deadlineAtMs: 1_800_000_000_000,
    });
  });

  it.each([
    ["入力がオブジェクトでない", "room1"],
    ["ルームの ID が無い", {}],
    ["ルームの ID にパスの区切り", { roomId: "a/b" }],
    ["ルーム名が空", { roomId: "r", name: "  " }],
    ["ルーム名が 21 文字", { roomId: "r", name: "あ".repeat(21) }],
    ["投稿数が 0", { roomId: "r", postLimit: 0 }],
    ["投稿数が 11", { roomId: "r", postLimit: 11 }],
    ["投稿数が小数", { roomId: "r", postLimit: 3.5 }],
    ["知らない条件", { roomId: "r", unlockRule: "someday" }],
    ["締切日時が文字列", { roomId: "r", deadlineAt: "2026-10-30" }],
    ["締切日時が小数", { roomId: "r", deadlineAt: 1.5 }],
    ["締切日時以外の条件に締切日時", { roomId: "r", unlockRule: "all", deadlineAt: 1_800_000_000_000 }],
    ["知らないいいねの効き方", { roomId: "r", likeMode: "double" }],
  ])("%s は invalid-argument", (_, data) => {
    expectInvalid(data);
  });
});
