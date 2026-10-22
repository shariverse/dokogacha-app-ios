/**
 * 引き直し（02 の §6.4・F-43）の過半数の判定。
 * Swift 側の `Dokogacha/Domain/Logic/RerollRule.swift` と同じ式で、同じケースを Jest と Swift Testing の両方で確かめる。
 *
 * 判定するのはサーバー（`voteReroll`・`proposeReroll`・`expireRerolls`・退出）で、アプリは同じ式を「賛成を集めています…（N/M人）」の
 * N（賛成の数）を数えるのに使う。
 */

/**
 * 賛成が過半数か（02 の §6.4「賛成が過半数（> メンバー数 ÷ 2）」）。
 * 割り算の誤差を避けるため、`賛成 × 2 > メンバー数` の整数で比べる。メンバーが 0 人なら可決しない。
 * @param approvals 賛成の数（`countApprovals` で数えたもの）
 * @param memberCount メンバーの数（作成者を含む）
 */
export function isRerollMajority(approvals: number, memberCount: number): boolean {
  return memberCount > 0 && approvals * 2 > memberCount;
}

/**
 * 賛成の数を数える。今のメンバーの票だけを、1 人 1 票で数える
 * （同じ uid が重なっていても 1 票。退出した人の票は退出のときに取り除くが、残っていても数えない）。
 * @param votesFor 賛成した人の uid（`reroll.votesFor`）
 * @param memberIds 今のメンバーの uid（`memberIds`）
 */
export function countApprovals(votesFor: readonly string[], memberIds: readonly string[]): number {
  const members = new Set(memberIds);
  return new Set(votesFor.filter((uid) => members.has(uid))).size;
}
