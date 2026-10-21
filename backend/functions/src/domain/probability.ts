/**
 * 出やすさ（02 の §4.2〜4.4・F-21〜F-23）の重み・確率・表示 %・レベル・人気の判定。
 * Swift 側の `Dokogacha/Domain/Logic/Probability.swift` と同じ式で、06 の §2 の同じケースを両方で確かめる。
 *
 * 抽選（`drawGacha`）は `weightOf` の重みで選び、`probabilitiesOf` の確率を抽選記録に残す。
 * 同じ値をアプリが表示に使うので、計算の順番（重みの合計は渡した順に左から足す・丸めは 0.5 を切り上げる）までそろえ、
 * 浮動小数点の結果を Swift と一致させる。
 */
import {
  ALL_LIKED_MIN_OTHER_MEMBERS,
  LEVEL_HIGH_RATIO_PERCENT,
  LEVEL_MID_RATIO_PERCENT,
  POPULAR_MIN_LIKES,
  POPULAR_RATIO,
} from "./constants";
import type { LikeMode } from "./models";

/** 出やすさのレベル（F-22）。flat = 平等・high = 出やすい・mid = ふつう・low = レア */
export type ProbabilityLevel = "flat" | "high" | "mid" | "low";

/** 人気の強調（F-23）。popular = みんな推し・allLiked = 全員いいね */
export type PopularityHighlight = "popular" | "allLiked";

/** 出やすさを計算する候補 1 件分の入力 */
export interface OddsInput {
  /** 候補の ID（`candidates/{candidateId}`） */
  readonly id: string;
  /** いいね数（`likedBy` の数） */
  readonly likeCount: number;
}

/** 候補 1 件分の出やすさ */
export interface CandidateOdds {
  /** 重み（F-21） */
  readonly weight: number;
  /** 確率（0〜1。重み ÷ 抽選の対象の重みの合計） */
  readonly probability: number;
  /** 表示 %（`round(確率 × 100)`） */
  readonly displayPercent: number;
  /** レベル（F-22） */
  readonly level: ProbabilityLevel;
}

/** ルームの全候補の出やすさ */
export interface OddsTable {
  /** 候補の ID ごとの出やすさ。抽選の対象から外れた候補（引き直しの除外）は入らない */
  readonly odds: ReadonlyMap<string, CandidateOdds>;
  /** 抽選の対象の候補の中で最大の表示 %。候補が無ければ 0 */
  readonly maxDisplayPercent: number;
}

/**
 * 候補の重み（F-21）。共感ブーストは `1 + sqrt(いいね数)`、みんな平等は `1`。
 * いいね数が負の値で来ても（壊れたデータ）0 とみなす。
 * @param likeCount いいね数
 * @param mode ルームのいいねの効き方
 */
export function weightOf(likeCount: number, mode: LikeMode): number {
  return mode === "equal" ? 1 : 1 + Math.sqrt(Math.max(likeCount, 0));
}

/**
 * 重みから確率を出す（F-21「確率 = 重み ÷ Σ重み」）。
 * 合計は渡した順に左から足す（Swift と同じ順にして結果を一致させる）。合計が 0 以下なら（候補が無いなど）すべて 0。
 * @param weights 抽選の対象の候補の重み
 * @returns 同じ順の確率
 */
export function probabilitiesOf(weights: readonly number[]): number[] {
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  if (total <= 0) {
    return weights.map(() => 0);
  }
  return weights.map((weight) => weight / total);
}

/**
 * 確率を表示 % にする（F-21「表示% = round(確率 × 100)」）。
 * 0.5 は切り上げる（`Math.round`。確率は 0 以上なので、Swift の `.toNearestOrAwayFromZero` と結果が同じ）。
 * 02 のとおり、全候補の表示 % の合計が 100 にならなくても合わせない。
 * @param probability 確率（0〜1）
 */
export function displayPercentOf(probability: number): number {
  return Math.round(probability * 100);
}

/**
 * 出やすさのレベル（F-22）。
 * みんな平等モードは常に「平等」。共感ブーストは「比 = 表示% ÷ 平均%（`100 / 候補数`）」で決める。
 * 比 × 100 は `表示% × 候補数` の整数になるので、整数どうしで境目と比べ、
 * 浮動小数点の誤差で「1.2 ちょうど」「0.85 ちょうど」が下のレベルに落ちないようにする。
 * @param displayPercent この候補の表示 %
 * @param candidateCount 抽選の対象の候補の数（平均 % の分母）
 * @param mode ルームのいいねの効き方
 */
export function levelOf(displayPercent: number, candidateCount: number, mode: LikeMode): ProbabilityLevel {
  if (mode !== "boost") {
    return "flat";
  }
  const ratioPercent = displayPercent * candidateCount;
  if (ratioPercent >= LEVEL_HIGH_RATIO_PERCENT) {
    return "high";
  }
  if (ratioPercent >= LEVEL_MID_RATIO_PERCENT) {
    return "mid";
  }
  return "low";
}

/**
 * ルームの全候補の出やすさ（F-21・F-22）をまとめて出す。
 * 引き直しで除外された候補（`rooms.excludedCandidateIds`）は抽選の対象から外し、
 * 重みの合計にも平均 % の分母にも入れない（表に入らない）。
 * @param candidates 候補（並びの順に重みを足す）
 * @param mode ルームのいいねの効き方
 * @param excludedIds 抽選の対象から外す候補の ID
 */
export function computeOdds(
  candidates: readonly OddsInput[],
  mode: LikeMode,
  excludedIds: readonly string[] = [],
): OddsTable {
  const excluded = new Set(excludedIds);
  const eligible = candidates.filter((candidate) => !excluded.has(candidate.id));
  const weights = eligible.map((candidate) => weightOf(candidate.likeCount, mode));
  const probabilities = probabilitiesOf(weights);
  const odds = new Map<string, CandidateOdds>();
  let maxDisplayPercent = 0;
  eligible.forEach((candidate, index) => {
    const weight = weights[index] ?? 0;
    const probability = probabilities[index] ?? 0;
    const displayPercent = displayPercentOf(probability);
    maxDisplayPercent = Math.max(maxDisplayPercent, displayPercent);
    odds.set(candidate.id, {
      weight,
      probability,
      displayPercent,
      level: levelOf(displayPercent, eligible.length, mode),
    });
  });
  return { odds, maxDisplayPercent };
}

/**
 * 人気の強調（F-23）。
 * 投稿者を除いたメンバー数 `n' = メンバー数 − 1` に対し、「全員いいね」は `いいね数 ≥ n'（かつ n' ≥ 2）`、
 * 「みんな推し」は `いいね数 ≥ ceil(n' × 0.6)（かついいね数 ≥ 2）`。両方に当てはまるときは「全員いいね」を優先する。
 * 基準の値は constants.ts（06 の §4 の仮決め）。
 * @param likeCount いいね数
 * @param memberCount ルームのメンバー数（投稿者を含む）
 * @returns 強調しないなら null
 */
export function highlightOf(likeCount: number, memberCount: number): PopularityHighlight | null {
  const otherMembers = memberCount - 1;
  if (otherMembers >= ALL_LIKED_MIN_OTHER_MEMBERS && likeCount >= otherMembers) {
    return "allLiked";
  }
  const popularThreshold = Math.ceil(otherMembers * POPULAR_RATIO);
  if (likeCount >= POPULAR_MIN_LIKES && likeCount >= popularThreshold) {
    return "popular";
  }
  return null;
}
