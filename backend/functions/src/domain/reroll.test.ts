import { countApprovals, isRerollMajority } from "./reroll";

// Swift 側の `DokogachaTests/RerollRuleTests.swift` と同じケース。片方を変えたら両方を変える。
describe("isRerollMajority（02 の §6.4「賛成が過半数（> メンバー数 ÷ 2）」）", () => {
  it.each([
    [1, 1, true],
    [1, 2, false],
    [2, 2, true],
    [1, 3, false],
    [2, 3, true],
    [2, 4, false],
    [3, 4, true],
    [2, 5, false],
    [3, 5, true],
    [10, 20, false],
    [11, 20, true],
    [0, 3, false],
    [0, 0, false],
  ])("賛成 %i / メンバー %i 人 → %p", (approvals, memberCount, expected) => {
    expect(isRerollMajority(approvals, memberCount)).toBe(expected);
  });
});

describe("countApprovals", () => {
  it("今のメンバーの票だけを 1 人 1 票で数える", () => {
    expect(countApprovals(["a", "b"], ["a", "b", "c"])).toBe(2);
    expect(countApprovals(["a", "a", "b"], ["a", "b", "c"])).toBe(2);
    expect(countApprovals(["a", "left"], ["a", "b"])).toBe(1);
    expect(countApprovals([], ["a"])).toBe(0);
  });
});
