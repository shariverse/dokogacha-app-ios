/**
 * 招待コード（02 の §2.4・F-04）の生成・表示・入力の正規化・検証。
 * Swift 側の `Dokogacha/Domain/Logic/InviteCode.swift` と同じ規則で、06 の §2 の同じケースを Jest と Swift Testing で確かめる。
 *
 * 保存する形はハイフンなしの 6 文字（`rooms.inviteCode`・`inviteCodes/{code}`）、表示は 3 文字ずつハイフンで区切る（`DK7-29Q`）。
 */
import { cryptoRandomInt, pickOne, type RandomInt } from "./random";

/** 使う文字（英大文字 24 文字と数字 8 文字の 32 文字）。紛らわしい `0 O 1 I` を除く */
export const INVITE_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
/** コードの文字数 */
export const INVITE_CODE_LENGTH = 6;
/** 表示でハイフンを入れる位置（先頭からの文字数） */
export const INVITE_CODE_GROUP_LENGTH = 3;
/** 表示の区切り */
export const INVITE_CODE_SEPARATOR = "-";

/**
 * 入力から取り除く文字（空白と、ハイフン・ダッシュ・マイナス・長音記号）。
 * 日本語の入力では、ハイフンのつもりで全角のハイフン・長音記号（ー）を打つことが多いため含める。
 * Swift 側の `InviteCode.ignoredSeparators` と `Character.isWhitespace` に合わせる。
 */
const IGNORED_CHARACTERS = /[\s\-‐‑‒–—―−ー]/gu;

/** 文字（書記素クラスタ）に分ける道具。Swift の `Character` と同じ単位で数える */
const graphemeSegmenter = new Intl.Segmenter("ja", { granularity: "grapheme" });

/**
 * 文字列を文字（書記素クラスタ）の一覧にする。
 * Swift 側は `String` の `count`・`prefix` が書記素クラスタで数えるので、文字数の判定と切り詰めをそろえるために使う。
 * @param text 分ける文字列
 * @returns 文字の一覧
 */
function characters(text: string): string[] {
  return Array.from(graphemeSegmenter.segment(text), (segment) => segment.segment);
}

/**
 * 招待コードを作る（32 文字から 1 文字ずつ、6 回選ぶ）。
 * 重複の確かめと再生成は呼ぶ側（`createRoom`）で行う。
 * @param random 乱数（既定は `crypto.randomInt`）
 * @returns ハイフンなしの 6 文字
 */
export function generateInviteCode(random: RandomInt = cryptoRandomInt): string {
  const alphabet = characters(INVITE_CODE_ALPHABET);
  return Array.from({ length: INVITE_CODE_LENGTH }, () => pickOne(alphabet, random)).join("");
}

/**
 * 入力の文字列を、招待コードの形に正規化する（検証はしない）。
 * 1. 全角の英数字・記号・空白を半角にする（NFKC）
 * 2. 空白と区切りの文字を取り除く
 * 3. 英字を大文字にする
 * @param input 入力された文字列
 * @returns 正規化した文字列（使えない文字はそのまま残す）
 */
export function normalizeInviteCode(input: string): string {
  return input.normalize("NFKC").replace(IGNORED_CHARACTERS, "").toUpperCase();
}

/**
 * 正規化済みの文字列が、招待コードとして正しいか（6 文字で、すべて使える文字）。
 * @param normalized `normalizeInviteCode` した文字列
 * @returns 正しければ true
 */
export function isValidInviteCode(normalized: string): boolean {
  const list = characters(normalized);
  return list.length === INVITE_CODE_LENGTH && list.every((character) => INVITE_CODE_ALPHABET.includes(character));
}

/**
 * 入力を正規化して、招待コードとして正しければ保存する形（ハイフンなしの 6 文字）を返す。
 * Callable（`joinRoom`）の入力の検証に使う。
 * @param input 入力された文字列
 * @returns 正しければハイフンなしの 6 文字、正しくなければ null
 */
export function parseInviteCode(input: string): string | null {
  const normalized = normalizeInviteCode(input);
  return isValidInviteCode(normalized) ? normalized : null;
}

/**
 * 文字列を表示の形にする（先頭から 3 文字目の後ろにハイフンを入れる）。3 文字以下ならそのまま。
 * 位置だけで区切り、使える文字かどうかは見ない。
 * @param code ハイフンなしの文字列
 * @returns 表示の形（`DK7-29Q`）
 */
export function formatInviteCode(code: string): string {
  const list = characters(code);
  if (list.length <= INVITE_CODE_GROUP_LENGTH) {
    return code;
  }
  return (
    list.slice(0, INVITE_CODE_GROUP_LENGTH).join("") +
    INVITE_CODE_SEPARATOR +
    list.slice(INVITE_CODE_GROUP_LENGTH).join("")
  );
}

/**
 * 入力欄に出す文字列（S-05「ハイフンは自動挿入、英大文字に自動変換、貼り付け対応」）。
 * 正規化して 6 文字までに切り、表示の形にする。Swift 側の `InviteCode.inputText` と同じ。
 * @param input 入力欄の文字列
 * @returns 入力欄に出し直す文字列
 */
export function inviteCodeInputText(input: string): string {
  return formatInviteCode(characters(normalizeInviteCode(input)).slice(0, INVITE_CODE_LENGTH).join(""));
}
