/**
 * 多くのドキュメント（ルーム）を、少しずつ並べて処理するための道具。
 * トリガー（`onUserProfileUpdate`）とスケジュール（`checkDeadlines`）で、同時に開くトランザクションの数を抑える。
 */

/**
 * 一覧を `size` 件ずつに分ける（ルームを少しずつ並べて処理し、同時に開くトランザクションの数を抑える）。
 * @param items 一覧
 * @param size 1 つの組の最大の件数（1 以上）
 * @returns 組の一覧（元の順を保つ）
 */
export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (!Number.isInteger(size) || size < 1) {
    throw new RangeError(`size は 1 以上の整数: ${String(size)}`);
  }
  const chunks: T[][] = [];
  for (let start = 0; start < items.length; start += size) {
    chunks.push(items.slice(start, start + size));
  }
  return chunks;
}
