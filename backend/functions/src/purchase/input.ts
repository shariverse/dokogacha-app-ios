/**
 * 広告非表示の購入の Callable（`verifyPurchase`）の入力の検証（02 の §7.2 F-51）。
 */
import { appError } from "../errors";
import { requireObject } from "../validation";

/**
 * 署名付きトランザクションの最大の長さ（文字数）。
 * StoreKit 2 の `jwsRepresentation` は証明書の連なり（3 枚）を含んで 4〜6 KB ほど。巨大な文字列を検証に回さないための上限
 */
export const MAX_SIGNED_TRANSACTION_LENGTH = 16 * 1024;

/** JWS の形（base64url の 3 つの部分を `.` でつないだもの） */
const JWS_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/u;

/** `verifyPurchase` の入力（検証済み） */
export interface VerifyPurchaseInput {
  /** StoreKit 2 の署名付きトランザクション（`Transaction` の `jwsRepresentation`） */
  signedTransaction: string;
}

/**
 * `verifyPurchase` の入力（`{ signedTransaction }`）を検証する。形だけを確かめ、署名は `verifier.ts` で確かめる。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseVerifyPurchaseInput(data: unknown): VerifyPurchaseInput {
  const input = requireObject(data);
  const signed = input.signedTransaction;
  if (typeof signed !== "string" || signed.length > MAX_SIGNED_TRANSACTION_LENGTH || !JWS_PATTERN.test(signed)) {
    throw appError("invalid-argument");
  }
  return { signedTransaction: signed };
}
