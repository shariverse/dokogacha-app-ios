import { parseCloseRoomInput } from "./input";

describe("parseCloseRoomInput", () => {
  it("ルームの ID と終了の意図（decide・endEarly）を受け付ける", () => {
    expect(parseCloseRoomInput({ roomId: "room1", reason: "decide" })).toEqual({ roomId: "room1", reason: "decide" });
    expect(parseCloseRoomInput({ roomId: "room1", reason: "endEarly" })).toEqual({ roomId: "room1", reason: "endEarly" });
  });

  it("意図が無ければ decide（意図を送らない前の版のアプリの「この行き先で決定」）", () => {
    expect(parseCloseRoomInput({ roomId: "room1" })).toEqual({ roomId: "room1", reason: "decide" });
  });

  it.each([
    undefined,
    null,
    [],
    { roomId: "room1", reason: "abandon" },
    { roomId: "room1", reason: null },
    { roomId: "room1", reason: 1 },
    { roomId: "", reason: "endEarly" },
    { roomId: "a/b", reason: "decide" },
  ])("%p は invalid-argument", (data) => {
    expect(() => parseCloseRoomInput(data)).toThrow(
      expect.objectContaining({ details: { reason: "invalid-argument" } }) as Error,
    );
  });
});
