/**
 * ドメインのロジックに注入する乱数。テストでは固定の値を返す関数を渡す。
 */
import { randomInt } from "node:crypto";

/** `0` 以上 `max` 未満の整数を返す乱数（`crypto.randomInt` と同じ形） */
export type RandomInt = (max: number) => number;

/** 暗号論的に安全な乱数（`crypto.randomInt`）。Functions で使うときの既定 */
export const cryptoRandomInt: RandomInt = (max) => randomInt(max);

/**
 * 一覧から 1 つを乱数で選ぶ。
 * @param values 選ぶ元（空でないこと）
 * @param random 乱数
 * @returns 選んだ値
 * @throws 一覧が空・乱数が範囲の外の整数でないとき
 */
export function pickOne<T>(values: readonly T[], random: RandomInt): T {
  const index = random(values.length);
  if (!Number.isInteger(index) || index < 0 || index >= values.length) {
    throw new RangeError(`乱数が 0〜${String(values.length - 1)} の整数ではありません: ${String(index)}`);
  }
  return values[index] as T;
}
