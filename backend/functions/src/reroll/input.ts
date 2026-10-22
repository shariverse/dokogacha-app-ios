/**
 * 引き直しの Callable（`proposeReroll`・`voteReroll`）の入力の検証。
 * `proposeReroll` の入力は `{ roomId }`（`unlock/input.ts` の `parseRoomIdInput`）。
 */
import { appError } from "../errors";
import { requireDocumentId, requireObject } from "../validation";

/** `voteReroll` の入力（検証済み。アプリの `VoteRerollRequest`） */
export interface VoteRerollInput {
  /** ルームの ID */
  roomId: string;
  /** 賛成なら true、反対なら false */
  approve: boolean;
}

/**
 * `{ roomId, approve }` の入力を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`（`approve` が真偽値でない・ルームの ID が正しくない）
 */
export function parseVoteRerollInput(data: unknown): VoteRerollInput {
  const input = requireObject(data);
  if (typeof input.approve !== "boolean") {
    throw appError("invalid-argument");
  }
  return { roomId: requireDocumentId(input.roomId), approve: input.approve };
}
