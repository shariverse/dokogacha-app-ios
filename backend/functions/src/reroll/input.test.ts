import { parseVoteRerollInput } from "./input";

describe("parseVoteRerollInput", () => {
  it("ルームの ID と賛成・反対を受け付ける", () => {
    expect(parseVoteRerollInput({ roomId: "room1", approve: true })).toEqual({ roomId: "room1", approve: true });
    expect(parseVoteRerollInput({ roomId: "room1", approve: false })).toEqual({ roomId: "room1", approve: false });
  });

  it.each([
    undefined,
    null,
    { roomId: "room1" },
    { roomId: "room1", approve: "true" },
    { roomId: "room1", approve: 1 },
    { roomId: "", approve: true },
    { roomId: "a/b", approve: false },
  ])("%p は invalid-argument", (data) => {
    expect(() => parseVoteRerollInput(data)).toThrow(
      expect.objectContaining({ details: { reason: "invalid-argument" } }) as Error,
    );
  });
});
