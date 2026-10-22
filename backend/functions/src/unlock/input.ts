/**
 * 解禁の Callable（`forceUnlock`）の入力の検証。
 */
import { requireDocumentId, requireObject } from "../validation";

/** ルームを 1 つ指す入力（検証済み） */
export interface RoomIdInput {
  /** ルームの ID */
  roomId: string;
}

/**
 * `{ roomId }` の入力を検証する。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseRoomIdInput(data: unknown): RoomIdInput {
  const input = requireObject(data);
  return { roomId: requireDocumentId(input.roomId) };
}
