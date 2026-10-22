import { chunk } from "./batch";

describe("chunk", () => {
  it("元の順を保って size 件ずつに分ける", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([1, 2], 2)).toEqual([[1, 2]]);
    expect(chunk([], 3)).toEqual([]);
  });

  it.each([0, -1, 1.5])("size が %p なら投げる", (size) => {
    expect(() => chunk([1], size)).toThrow(RangeError);
  });
});
