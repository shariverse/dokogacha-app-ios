/**
 * 抽選（02 の §6.1・F-40）の重み付きの選択。Firestore に触れない純粋な関数で、乱数は引数で注入する。
 * Swift 側の `Dokogacha/Domain/Logic/GachaDraw.swift` と同じ式で、06 の §2 の抽選のケースを両方で確かめる
 * （擬似のサーバーの `drawGacha` が使う。本物の抽選はサーバーの `drawGacha` だけが行う）。
 *
 * 選び方: 抽選の対象の候補を ID 順に並べ（`eligibleInIdOrder`）、重みの累積の区間 `[累積の前, 累積)` に
 * `u × 重みの合計`（`u = 乱数 ÷ DRAW_RANDOM_RANGE`。0 以上 1 未満）が入った候補を当選にする。
 * 重みの合計と累積は同じ順で左から足すので、確率（`computeOdds`）と区間の幅が一致する。
 */
import type { LikeMode } from "./models";
import { computeOdds, eligibleInIdOrder, weightOf, type OddsInput } from "./probability";
import type { RandomInt } from "./random";

/**
 * 乱数で引く整数の範囲（`0` 以上この値未満）。`crypto.randomInt` の上限（範囲が 2^48 未満）に収まる 2 の累乗にして、
 * `乱数 ÷ この値` を浮動小数点で誤差なく求める。重みの比が 2^47 分の 1 より細かい差は出ない（候補は最大 200 件で、重みは 1〜約 4.5）
 */
export const DRAW_RANDOM_RANGE = 2 ** 47;

/** 抽選の対象の候補 1 件（ID と重み） */
export interface DrawEntry {
  /** 候補の ID */
  readonly id: string;
  /** 重み（F-21） */
  readonly weight: number;
}

/** 抽選の結果（抽選の記録 `draws/{drawId}` に書く値） */
export interface DrawResult {
  /** 当選した候補の ID */
  readonly candidateId: string;
  /** 当選時の確率（0〜1。`computeOdds` の確率と同じ値） */
  readonly probability: number;
  /** 抽選時の重みのスナップショット（抽選の対象の候補の ID → 重み。除外した候補は入らない） */
  readonly weights: Record<string, number>;
}

/**
 * 抽選の対象の候補と重み（除外した候補を外し、ID 順に並べる）。
 * @param candidates ルームの候補（どの順でもよい）
 * @param mode ルームのいいねの効き方
 * @param excludedIds 引き直しで除外された候補の ID（`rooms.excludedCandidateIds`）
 */
export function drawEntriesOf(
  candidates: readonly OddsInput[],
  mode: LikeMode,
  excludedIds: readonly string[],
): DrawEntry[] {
  return eligibleInIdOrder(candidates, excludedIds).map((candidate) => ({
    id: candidate.id,
    weight: weightOf(candidate.likeCount, mode),
  }));
}

/**
 * 重み付きで 1 件を選ぶ（`entries` の順に累積を足す。並べ替えない）。
 * 重みが 0 以下の候補は区間の幅が 0 なので当選しない。
 * @param entries 抽選の対象の候補（ID 順に並べたもの。`drawEntriesOf`）
 * @param random 乱数（`DRAW_RANDOM_RANGE` を渡して 0 以上それ未満の整数を返す。サーバーでは `crypto.randomInt`）
 * @returns 当選した候補の ID
 * @throws 候補が無い・重みの合計が 0 以下・乱数が範囲の外の整数でないとき（呼ぶ側で候補が 0 件なら先に断る）
 */
export function pickWeighted(entries: readonly DrawEntry[], random: RandomInt): string {
  const total = entries.reduce((sum, entry) => sum + entry.weight, 0);
  if (entries.length === 0 || !(total > 0)) {
    throw new RangeError("抽選の対象の候補がありません");
  }
  const value = random(DRAW_RANDOM_RANGE);
  if (!Number.isInteger(value) || value < 0 || value >= DRAW_RANDOM_RANGE) {
    throw new RangeError(`乱数が 0〜${String(DRAW_RANDOM_RANGE - 1)} の整数ではありません: ${String(value)}`);
  }
  const target = (value / DRAW_RANDOM_RANGE) * total;
  let cumulative = 0;
  let lastPositive: string | null = null;
  for (const entry of entries) {
    if (entry.weight <= 0) {
      continue;
    }
    cumulative += entry.weight;
    lastPositive = entry.id;
    if (target < cumulative) {
      return entry.id;
    }
  }
  // 丸めで target が累積の最後に届いた（u < 1 なので通常は起きない）ときは、最後の重みのある候補にする
  return lastPositive as string;
}

/**
 * ルームの候補から抽選する（`drawGacha` のトランザクションの中で使う）。
 * @param candidates ルームの候補（どの順でもよい）
 * @param mode ルームのいいねの効き方
 * @param excludedIds 引き直しで除外された候補の ID
 * @param random 乱数
 * @returns 抽選の結果。抽選の対象の候補が 0 件なら null（`no-candidates` で断る）
 */
export function drawCandidate(
  candidates: readonly OddsInput[],
  mode: LikeMode,
  excludedIds: readonly string[],
  random: RandomInt,
): DrawResult | null {
  const entries = drawEntriesOf(candidates, mode, excludedIds);
  if (entries.length === 0) {
    return null;
  }
  const candidateId = pickWeighted(entries, random);
  const odds = computeOdds(candidates, mode, excludedIds).odds.get(candidateId);
  return {
    candidateId,
    probability: odds?.probability ?? 0,
    weights: Object.fromEntries(entries.map((entry) => [entry.id, entry.weight])),
  };
}
