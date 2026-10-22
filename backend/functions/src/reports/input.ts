/**
 * 投稿の報告の Callable（`reportCandidate`）の入力の検証（02 の §3.5・F-14）。
 */
import { isOneOf, REPORT_REASONS, type ReportReason } from "../domain/models";
import { appError } from "../errors";
import { requireDocumentId, requireObject } from "../validation";

/** `reportCandidate` の入力（検証済み） */
export interface ReportCandidateInput {
  /** ルームの ID */
  roomId: string;
  /** 報告する候補の ID */
  candidateId: string;
  /** 理由（不適切な内容／スパム／その他） */
  reason: ReportReason;
}

/**
 * `reportCandidate` の入力（`{ roomId, candidateId, reason }`）を検証する。
 * 理由は 3 つの値（`REPORT_REASONS`。アプリの `ReportReason` の `rawValue`）のどれかだけを受け付ける（自由入力の文は受け取らない）。
 * @param data `request.data`
 * @returns 検証した入力
 * @throws `invalid-argument`
 */
export function parseReportCandidateInput(data: unknown): ReportCandidateInput {
  const input = requireObject(data);
  const roomId = requireDocumentId(input.roomId);
  const candidateId = requireDocumentId(input.candidateId);
  if (!isOneOf(REPORT_REASONS, input.reason)) {
    throw appError("invalid-argument");
  }
  return { roomId, candidateId, reason: input.reason };
}
