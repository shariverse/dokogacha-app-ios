/**
 * 候補の Callable（`addCandidate`・`deleteCandidate`）の入力の検証。
 * 05 の §5 の入力を、型・範囲を確かめてから使う形にする。
 */
import { isAcceptableCandidateUrl } from "../domain/candidate";
import { isPlaceCategory, type PlaceCategory } from "../domain/category";
import {
  CANDIDATE_URL_MAX_LENGTH,
  MAP_ITEM_ID_MAX_LENGTH,
  NOTE_LENGTH,
  PLACE_AREA_LENGTH,
  PLACE_NAME_LENGTH,
} from "../domain/constants";
import type { Place } from "../domain/models";
import { containsForbiddenNameCharacter, isInvisibleOnly, trimWhitespace } from "../domain/text";
import { appError } from "../errors";
import { MAX_SURROUNDING_WHITESPACE_UTF16_UNITS, requireDocumentId, requireObject, requireTrimmedText } from "../validation";

/** `addCandidate` の入力（検証済み） */
export interface AddCandidateInput {
  /** ルームの ID */
  roomId: string;
  /** 場所（名前・エリアは前後の空白を取り除いたもの。識別子が無ければ null） */
  place: Place & { mapItemId: string | null };
  /** カテゴリ */
  category: PlaceCategory;
  /** ひとこと（前後の空白を取り除いた 0〜40 文字） */
  note: string;
  /** 参考 URL（前後の空白を取り除いたもの。無ければ null） */
  url: string | null;
  /** 過去のアイデアから持ち込んだときの元の ID（無ければ null） */
  fromPastIdeaId: string | null;
}

/**
 * 値が無い（`undefined`・`null`）か。任意の入力（05 の表で `?` のもの）に使う。
 * アプリ（Swift の `Codable`）は nil の値を鍵ごと送らないので、どちらも「無い」とみなす。
 */
function isAbsent(value: unknown): value is null | undefined {
  return value === undefined || value === null;
}

/**
 * 任意の文字列（0 文字から。エリア・ひとこと）を、名前と同じ規則で確かめる。
 * 見えない文字と空白だけなら空とみなすので、空の文字列にして保存する（ゼロ幅スペースだけのひとことを残さない）。
 * @throws `invalid-argument`
 */
function requireOptionalText(value: unknown, length: { min: 0; max: number }): string {
  const trimmed = requireTrimmedText(value, length);
  return isInvisibleOnly(trimmed) ? "" : trimmed;
}

/**
 * 範囲に入る有限の数か確かめる（緯度経度）。
 * @throws `invalid-argument`
 */
function requireNumberInRange(value: unknown, range: { min: number; max: number }): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < range.min || value > range.max) {
    throw appError("invalid-argument");
  }
  return value;
}

/**
 * MapKit の識別子（任意）を確かめる。無ければ null。
 * 中身は MapKit が決める文字列なので形は見ず、空でない・256 文字以下・前後に空白が無い・制御文字などを含まない文字列だけを受け付ける
 * （比べるのは完全一致なので、取り除かずに断る）。
 * @throws `invalid-argument`
 */
function parseMapItemId(value: unknown): string | null {
  if (isAbsent(value)) {
    return null;
  }
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAP_ITEM_ID_MAX_LENGTH ||
    trimWhitespace(value) !== value ||
    containsForbiddenNameCharacter(value)
  ) {
    throw appError("invalid-argument");
  }
  return value;
}

/**
 * 参考 URL（任意）を確かめる。無い・空白だけなら null（S-09 の「参考URL（任意）」を空のまま送ったとき）。
 * 前後の空白を取り除き、`http://`・`https://` で始まる 2048 文字以下の URL だけを受け付ける。
 * @throws `invalid-argument`
 */
function parseUrl(value: unknown): string | null {
  if (isAbsent(value)) {
    return null;
  }
  if (typeof value !== "string" || value.length > CANDIDATE_URL_MAX_LENGTH + MAX_SURROUNDING_WHITESPACE_UTF16_UNITS) {
    throw appError("invalid-argument");
  }
  const trimmed = trimWhitespace(value);
  if (trimmed === "") {
    return null;
  }
  if (trimmed.length > CANDIDATE_URL_MAX_LENGTH || !isAcceptableCandidateUrl(trimmed)) {
    throw appError("invalid-argument");
  }
  return trimmed;
}

/**
 * 場所（`{ name, area, latitude, longitude, mapItemId? }`）を確かめる。
 * - `name`: 1〜100 文字・`area`: 0〜50 文字（名前と同じ規則。前後の空白を取り除いて数える）
 * - `latitude`: -90〜90・`longitude`: -180〜180 の有限の数
 * @throws `invalid-argument`
 */
function parsePlace(value: unknown): AddCandidateInput["place"] {
  const place = requireObject(value);
  return {
    name: requireTrimmedText(place.name, PLACE_NAME_LENGTH),
    area: requireOptionalText(place.area, PLACE_AREA_LENGTH),
    latitude: requireNumberInRange(place.latitude, { min: -90, max: 90 }),
    longitude: requireNumberInRange(place.longitude, { min: -180, max: 180 }),
    mapItemId: parseMapItemId(place.mapItemId),
  };
}

/**
 * `addCandidate` の入力（`{ roomId, place, category, note, url?, fromPastIdeaId? }`）を検証する（02 の F-10）。
 * - `category`: 9 種のいずれか（02 の §3.1。アプリが自動判定し、S-09 で選び直せる）
 * - `note`: 0〜40 文字（名前と同じ規則。途中の改行・制御文字は受け付けない。見えない文字だけなら空にする）
 * - `fromPastIdeaId`: 過去のアイデア（F-13）から持ち込むときの元。ドキュメントの ID の形だけを確かめる
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseAddCandidateInput(data: unknown): AddCandidateInput {
  const input = requireObject(data);
  const roomId = requireDocumentId(input.roomId);
  const place = parsePlace(input.place);
  if (!isPlaceCategory(input.category)) {
    throw appError("invalid-argument");
  }
  const category = input.category;
  const note = requireOptionalText(input.note, NOTE_LENGTH);
  const url = parseUrl(input.url);
  const fromPastIdeaId = isAbsent(input.fromPastIdeaId) ? null : requireDocumentId(input.fromPastIdeaId);
  return { roomId, place, category, note, url, fromPastIdeaId };
}

/** `deleteCandidate` の入力（検証済み） */
export interface DeleteCandidateInput {
  /** ルームの ID */
  roomId: string;
  /** 候補の ID */
  candidateId: string;
}

/**
 * `deleteCandidate` の入力（`{ roomId, candidateId }`）を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseDeleteCandidateInput(data: unknown): DeleteCandidateInput {
  const input = requireObject(data);
  return { roomId: requireDocumentId(input.roomId), candidateId: requireDocumentId(input.candidateId) };
}
