import { parseRoomIdInput } from "./input";

describe("parseRoomIdInput", () => {
  it("ルームの ID を受け付ける", () => {
    expect(parseRoomIdInput({ roomId: "room1" })).toEqual({ roomId: "room1" });
  });

  it.each([undefined, null, [], { roomId: "" }, { roomId: "a/b" }, { roomId: 1 }])("%p は invalid-argument", (data) => {
    expect(() => parseRoomIdInput(data)).toThrow(expect.objectContaining({ details: { reason: "invalid-argument" } }) as Error);
  });
});
