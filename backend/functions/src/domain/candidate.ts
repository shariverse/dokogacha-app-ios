/**
 * 候補の判定（02 の F-10 の重複・05 の §3 の `colorIndex`・参考 URL の形）。Firestore に触れない純粋な関数。
 * Swift 側の `Dokogacha/Domain/Logic/CandidateRules.swift` と同じ式で、`candidate.test.ts` と同じケースを
 * `CandidateRulesTests` で確かめる。片方を変えたら両方を変える。
 */
import { DUPLICATE_DISTANCE_METERS } from "./constants";
import { containsForbiddenNameCharacter, isWhitespaceCodePoint } from "./text";

/**
 * 地球の半径（メートル。距離の計算に使う平均半径）。
 * 100m の判定には、楕円体と球の差（0.5% 未満）は効かないので球で計算する。Swift 側も同じ値。
 */
export const EARTH_RADIUS_METERS = 6_371_000;

/** 緯度経度 */
export interface Coordinate {
  /** 緯度（度） */
  latitude: number;
  /** 経度（度） */
  longitude: number;
}

/** 同じ場所かの判定に使う、場所の値（`candidates.place` の一部） */
export interface PlaceIdentity extends Coordinate {
  /** 場所名（前後の空白を取り除いたもの） */
  name: string;
  /** MapKit の識別子（取れなかったときは null か無し） */
  mapItemId?: string | null;
}

/**
 * 2 点の間の距離（メートル）を、球面の大円距離（ハーバーサインの式）で求める。
 * @param a 1 点目
 * @param b 2 点目
 * @returns 距離（メートル）
 */
export function distanceMeters(a: Coordinate, b: Coordinate): number {
  const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;
  const deltaLatitude = toRadians(b.latitude - a.latitude);
  const deltaLongitude = toRadians(b.longitude - a.longitude);
  const h =
    Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(toRadians(a.latitude)) * Math.cos(toRadians(b.latitude)) * Math.sin(deltaLongitude / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * 同じ場所か（02 の F-10「MapKit の識別子が同じ、または場所名が同じで座標が100m以内」）。
 * - 識別子はどちらにもあって等しいときだけ「同じ」とみなす（片方に無ければ、名前と距離で判定する）
 * - 場所名は前後の空白を取り除いた文字列どうしの完全一致（大文字・小文字・全角・半角を区別する）
 * - 100m ちょうどは「以内」に入る
 * @param a 1 つ目の場所
 * @param b 2 つ目の場所
 * @returns 同じ場所なら true
 */
export function isSamePlace(a: PlaceIdentity, b: PlaceIdentity): boolean {
  const aId = a.mapItemId ?? null;
  const bId = b.mapItemId ?? null;
  if (aId !== null && bId !== null && aId === bId) {
    return true;
  }
  return a.name === b.name && distanceMeters(a, b) <= DUPLICATE_DISTANCE_METERS;
}

/** 重複の判定と採番に使う、既存の候補 */
export interface ExistingCandidate {
  /** 候補の ID */
  id: string;
  /** 場所 */
  place: PlaceIdentity;
  /** 投稿した人の uid */
  postedBy: string;
  /** 投稿順の通し番号 */
  colorIndex: number;
  /** 投稿日時（UNIX 時刻のミリ秒） */
  createdAtMs: number;
}

/**
 * 同じ場所の既存の候補を探す（02 の F-10。自分の投稿も対象）。
 * 同じ場所が複数あるときは、いちばん古い投稿（同じ日時なら ID の順で先のもの）を返す。
 * @param place 追加しようとしている場所
 * @param existing ルームの既存の候補
 * @returns 重複した候補の ID（無ければ null）
 */
export function findDuplicateCandidate(place: PlaceIdentity, existing: readonly ExistingCandidate[]): string | null {
  const matches = existing
    .filter((candidate) => isSamePlace(place, candidate.place))
    .sort((a, b) => a.createdAtMs - b.createdAtMs || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return matches[0]?.id ?? null;
}

/**
 * 新しい候補の `colorIndex`（05 の §3「投稿順の通し番号（カプセルの色に使う）」）。
 * 既存の候補の最大の番号 + 1（候補が無ければ 0）。候補を消しても残りの番号は詰めない
 * （カプセルの色が変わらないように）。いちばん新しい候補を消したときだけ、その番号が次の投稿で再び使われる。
 * @param existing ルームの既存の候補の `colorIndex`
 * @returns 新しい候補の番号
 */
export function nextColorIndex(existing: readonly number[]): number {
  return existing.reduce((max, index) => Math.max(max, index + 1), 0);
}

/** 参考 URL の先頭に許すスキーム（小文字にして比べる） */
const URL_SCHEMES = ["http://", "https://"] as const;

/**
 * 参考 URL として受け付ける形か（前後の空白を取り除いた後の文字列に使う）。
 * - `http://` か `https://` で始まる（大文字・小文字を区別しない）。その後に 1 文字以上ある
 * - 途中に空白（`WHITESPACE_CODE_POINTS`）・制御文字・行と段落の区切りを含まない
 *
 * URL の解析器は言語ごとに受け付ける範囲が違うので使わず、Swift と同じ結果になる文字の規則だけで判定する。
 * 長さの上限（`CANDIDATE_URL_MAX_LENGTH`）は呼ぶ側で見る。
 * @param trimmed 前後の空白を取り除いた URL
 * @returns 受け付けるなら true
 */
export function isAcceptableCandidateUrl(trimmed: string): boolean {
  const lower = trimmed.toLowerCase();
  const scheme = URL_SCHEMES.find((prefix) => lower.startsWith(prefix));
  if (scheme === undefined || trimmed.length <= scheme.length) {
    return false;
  }
  if (containsForbiddenNameCharacter(trimmed)) {
    return false;
  }
  return !Array.from(trimmed).some((point) => isWhitespaceCodePoint(point.codePointAt(0) ?? -1));
}
