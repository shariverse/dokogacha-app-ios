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

/**
 * 一覧を `size` 件ずつの組に分け、組の中は並べて `run` を呼ぶ。
 *
 * 失敗した要素があっても、残りの要素（同じ組のほかの要素と、後の組）を最後まで処理してから、失敗をまとめて投げる
 * （`AggregateError`）。トリガー・スケジュールはこの例外でやり直す（`retry: true`）。`run` は冪等にしておき
 * （今の値と同じなら書かない）、やり直しで成功済みの要素を書き直さないようにする。
 * @param items 一覧
 * @param size 1 つの組の最大の件数（1 以上）
 * @param run 要素 1 つの処理
 * @returns 成功した要素の結果（元の順。すべて成功したときだけ返る）
 * @throws `AggregateError`（1 つでも失敗したとき。`errors` に失敗の理由を元の順で入れる）
 */
export async function settleInGroups<T, Result>(
  items: readonly T[],
  size: number,
  run: (item: T) => Promise<Result>,
): Promise<Result[]> {
  const results: Result[] = [];
  const errors: unknown[] = [];
  for (const group of chunk(items, size)) {
    const settled = await Promise.allSettled(group.map(run));
    for (const outcome of settled) {
      if (outcome.status === "fulfilled") {
        results.push(outcome.value);
      } else {
        errors.push(outcome.reason);
      }
    }
  }
  if (errors.length > 0) {
    throw new AggregateError(errors, `${String(errors.length)} / ${String(items.length)} 件の処理に失敗した`);
  }
  return results;
}
