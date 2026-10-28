import { chunk, settleInGroups } from "./batch";

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

describe("settleInGroups", () => {
  /** 1〜n の一覧 */
  const numbers = (n: number) => Array.from({ length: n }, (_, index) => index + 1);

  it("すべて成功したら、結果を元の順で返す", async () => {
    await expect(settleInGroups(numbers(5), 2, (value) => Promise.resolve(value * 10))).resolves.toEqual([
      10, 20, 30, 40, 50,
    ]);
    await expect(settleInGroups([], 3, () => Promise.resolve(0))).resolves.toEqual([]);
  });

  it("組の中は並べて、組どうしは順に処理する（同時に動くのは size 件まで）", async () => {
    let running = 0;
    let maxRunning = 0;
    await settleInGroups(numbers(25), 10, async () => {
      running += 1;
      maxRunning = Math.max(maxRunning, running);
      await new Promise((resolve) => setImmediate(resolve));
      running -= 1;
    });
    expect(maxRunning).toBe(10);
  });

  it("失敗があっても残りの組を最後まで処理し、最後に失敗をまとめて投げる", async () => {
    const called: number[] = [];
    const outcome = settleInGroups(numbers(25), 10, (value) => {
      called.push(value);
      return value === 3 || value === 15 ? Promise.reject(new Error(`失敗 ${String(value)}`)) : Promise.resolve(value);
    });
    await expect(outcome).rejects.toBeInstanceOf(AggregateError);
    await expect(outcome).rejects.toMatchObject({
      errors: [new Error("失敗 3"), new Error("失敗 15")],
      message: "2 / 25 件の処理に失敗した",
    });
    expect(called.sort((a, b) => a - b)).toEqual(numbers(25));
  });
});
