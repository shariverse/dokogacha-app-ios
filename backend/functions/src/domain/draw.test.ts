import { computeOdds, type OddsInput } from "./probability";
import { DRAW_RANDOM_RANGE, drawCandidate, drawEntriesOf, pickWeighted, type DrawEntry } from "./draw";
import type { RandomInt } from "./random";

// 06 の §2「抽選（F-40）」: 固定シードで同じ結果／1 万回試行の当選率が理論値 ±2%／除外リストの候補は当選しない。
// Swift 側の DokogachaTests/GachaDrawTests.swift と同じケース（同じシードの乱数で同じ当選の並び）。片方を変えたら両方を変える。

/** 02 の §4.2 の例のいいね数 */
const EXAMPLE_LIKES = [4, 3, 3, 2, 2, 1, 1, 0];

/** 1 万回の試行 */
const TRIALS = 10_000;

/** 当選率と理論値の差の許容（02 の F-40 の AC「理論値±2%以内」。確率の差で 0.02） */
const TOLERANCE = 0.02;

/** 固定のシード（Swift と同じ値） */
const SEED = 20261022;

/** 固定のシードで最初の 12 回に当選する候補（02 の例・共感ブースト。Swift の `GachaDrawTests.seededWinners` と同じ） */
const SEEDED_WINNERS = ["c3", "c1", "c3", "c2", "c0", "c2", "c1", "c5", "c2", "c2", "c5", "c3"];

/** いいね数の一覧から、`c0`・`c1`… の ID の入力を作る */
function inputs(likes: readonly number[]): OddsInput[] {
  return likes.map((likeCount, index) => ({ id: `c${String(index)}`, likeCount }));
}

/**
 * シードから同じ並びの乱数を作る（mulberry32。テストだけで使う。Swift の `GachaDrawTests.seeded` と同じ式）。
 * `random(max)` は `floor(0 以上 1 未満の値 × max)`。
 */
function seeded(seed: number): RandomInt {
  let state = seed >>> 0;
  return (max) => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    const unit = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    return Math.floor(unit * max);
  };
}

/** 決まった値を返す乱数 */
function fixed(value: number): RandomInt {
  return () => value;
}

/** `trials` 回抽選して、候補の ID ごとの当選数を数える */
function countWins(entries: readonly DrawEntry[], random: RandomInt, trials: number): Map<string, number> {
  const wins = new Map<string, number>();
  for (let index = 0; index < trials; index += 1) {
    const winner = pickWeighted(entries, random);
    wins.set(winner, (wins.get(winner) ?? 0) + 1);
  }
  return wins;
}

describe("抽選の重み付きの選択（F-40）", () => {
  it("06 の §2: 固定シードで同じ結果（同じシードなら同じ並び。Swift と同じ当選の並び）", () => {
    const entries = drawEntriesOf(inputs(EXAMPLE_LIKES), "boost", []);
    const first = seeded(SEED);
    const second = seeded(SEED);
    const winners = Array.from({ length: SEEDED_WINNERS.length }, () => pickWeighted(entries, first));
    expect(winners).toEqual(SEEDED_WINNERS);
    expect(Array.from({ length: SEEDED_WINNERS.length }, () => pickWeighted(entries, second))).toEqual(winners);
  });

  it.each(["boost", "equal"] as const)(
    "06 の §2: 1 万回試行の当選率が理論値 ±2% 以内（%s）",
    (mode) => {
      const candidates = inputs(EXAMPLE_LIKES);
      const wins = countWins(drawEntriesOf(candidates, mode, []), seeded(SEED), TRIALS);
      for (const [id, odds] of computeOdds(candidates, mode).odds) {
        expect(Math.abs((wins.get(id) ?? 0) / TRIALS - odds.probability)).toBeLessThanOrEqual(TOLERANCE);
      }
    },
  );

  it("いいねが多い候補ほど当選しやすい（共感ブーストで、いいね 4 の候補はいいね 0 の候補より多く当選する）", () => {
    const wins = countWins(drawEntriesOf(inputs(EXAMPLE_LIKES), "boost", []), seeded(SEED), TRIALS);
    expect(wins.get("c0") ?? 0).toBeGreaterThan(wins.get("c7") ?? 0);
  });

  it("06 の §2: 除外リストの候補は当選しない（1 万回のうち 0 回）", () => {
    const entries = drawEntriesOf(inputs(EXAMPLE_LIKES), "boost", ["c0", "c3"]);
    expect(entries.map((entry) => entry.id)).toEqual(["c1", "c2", "c4", "c5", "c6", "c7"]);
    const wins = countWins(entries, seeded(SEED), TRIALS);
    expect(wins.has("c0")).toBe(false);
    expect(wins.has("c3")).toBe(false);
    // 乱数が 0（区間の先頭）でも、除外した先頭の c0 ではなく次の c1 が当たる
    expect(pickWeighted(entries, fixed(0))).toBe("c1");
  });

  it("境目: 重み [1, 2, 1] の区間は [0, 1/4)・[1/4, 3/4)・[3/4, 1)（Swift と同じ値）", () => {
    const entries: DrawEntry[] = [
      { id: "a", weight: 1 },
      { id: "b", weight: 2 },
      { id: "c", weight: 1 },
    ];
    const quarter = DRAW_RANDOM_RANGE / 4;
    expect(pickWeighted(entries, fixed(0))).toBe("a");
    expect(pickWeighted(entries, fixed(quarter - 1))).toBe("a");
    expect(pickWeighted(entries, fixed(quarter))).toBe("b");
    expect(pickWeighted(entries, fixed(quarter * 3 - 1))).toBe("b");
    expect(pickWeighted(entries, fixed(quarter * 3))).toBe("c");
    expect(pickWeighted(entries, fixed(DRAW_RANDOM_RANGE - 1))).toBe("c");
  });

  it("候補 1 件なら、乱数によらずその候補が当選する", () => {
    const entries = drawEntriesOf(inputs([3]), "boost", []);
    expect(pickWeighted(entries, fixed(0))).toBe("c0");
    expect(pickWeighted(entries, fixed(DRAW_RANDOM_RANGE - 1))).toBe("c0");
  });

  it("重みが 0 の候補は当選しない（区間の幅が 0）", () => {
    const entries: DrawEntry[] = [
      { id: "a", weight: 0 },
      { id: "b", weight: 1 },
      { id: "c", weight: 0 },
    ];
    expect(pickWeighted(entries, fixed(0))).toBe("b");
    expect(pickWeighted(entries, fixed(DRAW_RANDOM_RANGE - 1))).toBe("b");
  });

  it("渡す順によらず、候補の ID 順に区間を並べる（Firestore から読んだ順に左右されない）", () => {
    const candidates = inputs(EXAMPLE_LIKES);
    const reversed = [...candidates].reverse();
    expect(drawEntriesOf(reversed, "boost", [])).toEqual(drawEntriesOf(candidates, "boost", []));
    expect(pickWeighted(drawEntriesOf(reversed, "boost", []), fixed(0))).toBe("c0");
  });

  it("乱数に DRAW_RANDOM_RANGE（2^47。crypto.randomInt の上限に収まる）を渡す", () => {
    const requested: number[] = [];
    pickWeighted([{ id: "a", weight: 1 }], (max) => {
      requested.push(max);
      return 0;
    });
    expect(requested).toEqual([2 ** 47]);
  });

  it("候補が無い・乱数が範囲の外の整数でないときは投げる", () => {
    expect(() => pickWeighted([], fixed(0))).toThrow(RangeError);
    expect(() => pickWeighted([{ id: "a", weight: 0 }], fixed(0))).toThrow(RangeError);
    for (const value of [-1, DRAW_RANDOM_RANGE, 0.5, Number.NaN]) {
      expect(() => pickWeighted([{ id: "a", weight: 1 }], fixed(value))).toThrow(RangeError);
    }
  });
});

describe("drawCandidate（drawGacha が書く抽選の記録の値）", () => {
  it("当選時の確率は出やすさの表（computeOdds）と同じ値で、重みのスナップショットは抽選の対象の候補だけ", () => {
    const candidates = inputs(EXAMPLE_LIKES);
    const result = drawCandidate(candidates, "boost", ["c7"], fixed(0));
    expect(result).not.toBeNull();
    expect(result?.candidateId).toBe("c0");
    expect(result?.probability).toBe(computeOdds(candidates, "boost", ["c7"]).odds.get("c0")?.probability);
    expect(Object.keys(result?.weights ?? {})).toEqual(["c0", "c1", "c2", "c3", "c4", "c5", "c6"]);
    expect(result?.weights.c0).toBe(3);
  });

  it("みんな平等では、どの候補も重み 1・確率 1/候補数", () => {
    const result = drawCandidate(inputs([5, 0, 0, 0]), "equal", [], fixed(DRAW_RANDOM_RANGE - 1));
    expect(result).toEqual({ candidateId: "c3", probability: 0.25, weights: { c0: 1, c1: 1, c2: 1, c3: 1 } });
  });

  it("候補が無い・すべて除外したときは null（no-candidates で断る）", () => {
    expect(drawCandidate([], "boost", [], fixed(0))).toBeNull();
    expect(drawCandidate(inputs([1, 2]), "boost", ["c0", "c1"], fixed(0))).toBeNull();
  });
});
