import { MAX_MEMBERS } from "./constants";
import type { LikeMode } from "./models";
import {
  compareCandidateIds,
  computeOdds,
  displayPercentOf,
  eligibleInIdOrder,
  highlightOf,
  levelOf,
  probabilitiesOf,
  weightOf,
  type CandidateOdds,
  type OddsInput,
  type OddsTable,
  type PopularityHighlight,
} from "./probability";

// 06 の §2「重み・確率（F-21）」「レベル（F-22）」「人気（F-23）」。
// Swift 側の DokogachaTests/ProbabilityTests.swift と同じケース。片方を変えたら両方を変える。

/** 02 の §4.2 の例のいいね数 */
const EXAMPLE_LIKES = [4, 3, 3, 2, 2, 1, 1, 0];

/**
 * 02 の §4.2 の例の確率（候補の ID 順 c0〜c7 に重みを足したときの値。Swift の `ProbabilityTests.exampleProbabilities` と同じ）。
 * 浮動小数点の最下位のビットまで比べる（足す順を逆にすると合計が 18.29252873988394 になり、値がずれる）
 */
const EXAMPLE_PROBABILITIES = [
  0.16400138234901213, 0.1493533696963436, 0.1493533696963436, 0.13197812050497354, 0.13197812050497354,
  0.10933425489934143, 0.10933425489934143, 0.05466712744967071,
];

/** いいね数の一覧から、`c0`・`c1`… の ID の入力を作る */
function inputs(likes: readonly number[]): OddsInput[] {
  return likes.map((likeCount, index) => ({ id: `c${String(index)}`, likeCount }));
}

/** 表の出やすさを、入力の順に並べる（除外した候補は undefined） */
function ordered(table: OddsTable, count: number): (CandidateOdds | undefined)[] {
  return Array.from({ length: count }, (_, index) => table.odds.get(`c${String(index)}`));
}

/** 表の出やすさを、入力の順に並べる（除外した候補が無いこと） */
function orderedAll(table: OddsTable, count: number): CandidateOdds[] {
  return ordered(table, count).map((odds) => {
    if (odds === undefined) {
      throw new Error("候補の出やすさが無い");
    }
    return odds;
  });
}

/** 小数第 2 位で丸める */
function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/** 合計 */
function sum(values: Iterable<number>): number {
  let total = 0;
  for (const value of values) {
    total += value;
  }
  return total;
}

/** 表のすべての値 */
function values(table: OddsTable): CandidateOdds[] {
  return [...table.odds.values()];
}

describe("重み・確率（F-21）", () => {
  it("02 の §4.2 の例: いいね [4,3,3,2,2,1,1,0] → 重み [3.00, 2.73, …]・合計 18.29・表示 [16,15,15,13,13,11,11,5]%", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "boost");
    const odds = orderedAll(table, EXAMPLE_LIKES.length);
    expect(odds.map((o) => round2(o.weight))).toEqual([3.0, 2.73, 2.73, 2.41, 2.41, 2.0, 2.0, 1.0]);
    expect(round2(sum(odds.map((o) => o.weight)))).toBe(18.29);
    expect(odds.map((o) => o.displayPercent)).toEqual([16, 15, 15, 13, 13, 11, 11, 5]);
    expect(table.maxDisplayPercent).toBe(16);
  });

  it("02 の §4.2 の例の確率は、渡す順によらず候補の ID 順に足した値と完全に一致する（Swift と同じ値）", () => {
    const forward = computeOdds(inputs(EXAMPLE_LIKES), "boost");
    const reversed = computeOdds([...inputs(EXAMPLE_LIKES)].reverse(), "boost");
    expect(orderedAll(forward, EXAMPLE_LIKES.length).map((odds) => odds.probability)).toEqual(EXAMPLE_PROBABILITIES);
    expect(orderedAll(reversed, EXAMPLE_LIKES.length).map((odds) => odds.probability)).toEqual(EXAMPLE_PROBABILITIES);
  });

  it("候補の ID 順は UTF-16 のコード単位の辞書順で、除外した候補を外す", () => {
    const ids = ["b", "a", "B", "aa", "\u{1F600}", "\uFF21", "c"];
    expect(eligibleInIdOrder(ids.map((id) => ({ id })), ["c"]).map((candidate) => candidate.id)).toEqual([
      "B",
      "a",
      "aa",
      "b",
      "\u{1F600}",
      "\uFF21",
    ]);
    expect(compareCandidateIds("a", "a")).toBe(0);
  });

  it("表示 % の合計は 100 にそろえない（例では 99）", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "boost");
    expect(sum(values(table).map((o) => o.displayPercent))).toBe(99);
    const equal = computeOdds(inputs([0, 0, 0]), "equal");
    expect(values(equal).map((o) => o.displayPercent)).toEqual([33, 33, 33]);
  });

  it("確率の合計は 1（丸める前）", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "boost");
    expect(Math.abs(sum(values(table).map((o) => o.probability)) - 1)).toBeLessThan(1e-12);
  });

  it("みんな平等では、いいね数に関係なく全候補が同じ %", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "equal");
    expect(new Set(values(table).map((o) => o.displayPercent))).toEqual(new Set([13]));
    expect(new Set(values(table).map((o) => o.weight))).toEqual(new Set([1]));
  });

  it.each<LikeMode>(["boost", "equal"])("候補 1 件なら 100%（%s）", (mode) => {
    const table = computeOdds(inputs([3]), mode);
    expect(table.odds.get("c0")?.displayPercent).toBe(100);
    expect(table.maxDisplayPercent).toBe(100);
  });

  it("候補 0 件なら表は空で、最大の表示 % は 0", () => {
    const table = computeOdds([], "boost");
    expect(table.odds.size).toBe(0);
    expect(table.maxDisplayPercent).toBe(0);
  });

  it("全候補のいいね数が同じなら、共感ブーストでも同じ %（レベルは「ふつう」）", () => {
    const table = computeOdds(inputs([2, 2, 2, 2]), "boost");
    expect(new Set(values(table).map((o) => o.displayPercent))).toEqual(new Set([25]));
    expect(new Set(values(table).map((o) => o.level))).toEqual(new Set(["mid"]));
  });

  it("引き直しで除外した候補は、表に入らず、合計と平均の分母からも外れる", () => {
    const table = computeOdds(inputs([4, 0, 0]), "boost", ["c0"]);
    expect(table.odds.has("c0")).toBe(false);
    expect(table.odds.get("c1")?.displayPercent).toBe(50);
    expect(table.odds.get("c2")?.displayPercent).toBe(50);
    expect(table.odds.get("c1")?.level).toBe("mid");
    expect(table.maxDisplayPercent).toBe(50);
  });

  it("全候補を除外したら表は空", () => {
    const table = computeOdds(inputs([1, 2]), "boost", ["c0", "c1"]);
    expect(table.odds.size).toBe(0);
    expect(table.maxDisplayPercent).toBe(0);
  });

  it("重みの式: 共感ブーストは 1 + √いいね数、みんな平等は 1。負のいいね数は 0 とみなす", () => {
    expect(weightOf(0, "boost")).toBe(1);
    expect(weightOf(4, "boost")).toBe(3);
    expect(weightOf(9, "equal")).toBe(1);
    expect(weightOf(-1, "boost")).toBe(1);
  });

  it("表示 % の丸めは 0.5 を切り上げる", () => {
    expect(displayPercentOf(0.125)).toBe(13);
    expect(displayPercentOf(0.124)).toBe(12);
    expect(displayPercentOf(0)).toBe(0);
    expect(displayPercentOf(1)).toBe(100);
  });

  it("合計が 0 の重みからは確率 0", () => {
    expect(probabilitiesOf([])).toEqual([]);
    expect(probabilitiesOf([0, 0])).toEqual([0, 0]);
  });
});

describe("レベル（F-22）", () => {
  it("06 の §2: 比 1.2 ちょうどで「出やすい」、0.85 ちょうどで「ふつう」、0.84 で「レア」", () => {
    expect(levelOf(24, 5, "boost")).toBe("high");
    expect(levelOf(23, 5, "boost")).toBe("mid");
    expect(levelOf(17, 5, "boost")).toBe("mid");
    expect(levelOf(21, 4, "boost")).toBe("low");
  });

  it("平均 % が割り切れない候補数でも、比 1.2 ちょうどは「出やすい」（3 候補・40%）", () => {
    expect(levelOf(40, 3, "boost")).toBe("high");
    expect(levelOf(39, 3, "boost")).toBe("mid");
  });

  it("02 の §4.2 の例のレベル（平均 12.5%）", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "boost");
    expect(ordered(table, EXAMPLE_LIKES.length).map((o) => o?.level)).toEqual([
      "high",
      "high",
      "high",
      "mid",
      "mid",
      "mid",
      "mid",
      "low",
    ]);
  });

  it("みんな平等モードでは全候補が「平等」", () => {
    const table = computeOdds(inputs(EXAMPLE_LIKES), "equal");
    expect(new Set(values(table).map((o) => o.level))).toEqual(new Set(["flat"]));
    expect(levelOf(100, 5, "equal")).toBe("flat");
  });
});

describe("人気（F-23）", () => {
  it("06 の §2: 5 人ルーム（n' = 4）でいいね 2 → なし、3 → みんな推し、4 → 全員いいね", () => {
    expect(highlightOf(2, 5)).toBeNull();
    expect(highlightOf(3, 5)).toBe("popular");
    expect(highlightOf(4, 5)).toBe("allLiked");
  });

  it("06 の §2: 2 人ルーム（n' = 1）ではいいね 1 でもリボンなし", () => {
    expect(highlightOf(1, 2)).toBeNull();
    expect(highlightOf(0, 2)).toBeNull();
  });

  it("3 人ルーム（n' = 2）では、いいね 2 は「全員いいね」（みんな推しより優先）、1 はなし", () => {
    expect(highlightOf(1, 3)).toBeNull();
    expect(highlightOf(2, 3)).toBe("allLiked");
  });

  it("1 人ルームではリボンなし", () => {
    expect(highlightOf(0, 1)).toBeNull();
  });

  it("「みんな推し」の下限は、n' = 1〜19 のすべてで ceil(n' × 0.6)（整数で書いた (3n' + 4) / 5）と 2 の大きい方", () => {
    for (let otherMembers = 1; otherMembers <= MAX_MEMBERS - 1; otherMembers += 1) {
      const threshold = Math.max(Math.floor((3 * otherMembers + 4) / 5), 2);
      for (let likes = 0; likes <= otherMembers; likes += 1) {
        let expected: PopularityHighlight | null = null;
        if (otherMembers >= 2 && likes >= otherMembers) {
          expected = "allLiked";
        } else if (likes >= threshold) {
          expected = "popular";
        }
        expect([otherMembers, likes, highlightOf(likes, otherMembers + 1)]).toEqual([otherMembers, likes, expected]);
      }
    }
  });
});
