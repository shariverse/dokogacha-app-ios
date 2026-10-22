/**
 * 投稿の報告（05 の §5 の `reportCandidate`・02 の §3.5 F-14）。
 * 報告（`reports/{id}`）と、運営に送るメール（Trigger Email 拡張が読む `mail/{id}`）を、1 つのトランザクションで作る
 * （報告だけ残ってメールが無い・同時に 2 回押して 2 通届く、を起こさない）。判定は `logic.ts`、入力の検証は `input.ts`。
 */
import { FieldValue } from "firebase-admin/firestore";

import { getRoomAsMember } from "../candidates/service";
import type { CandidateDoc, ReportDoc } from "../domain/models";
import type { ServiceDeps } from "../deps";
import { appError } from "../errors";
import { candidatesRef, mailRef, reportRef, roomRef } from "../paths";
import { parseReportCandidateInput } from "./input";
import { decideReport, reportDocumentId, reportMailOf, snapshotOf } from "./logic";

/** `reportCandidate` の結果 */
export interface ReportCandidateResult {
  /** 同じ人がこの候補をもう報告していたか（true なら今回は何も作っていない） */
  alreadyReported: boolean;
  /** 運営に送るメールを書いたか（宛先のパラメータが空なら false。報告は保存する） */
  mailQueued: boolean;
}

/** 報告のメールの送り先の設定 */
export interface ReportMailSettings {
  /** 宛先（Functions のパラメータ `REPORT_MAIL_TO` の値） */
  to: string;
}

/**
 * 候補を報告する（02 の §3.5）。
 * - ルームのメンバーだけ（`room-not-found`・`not-room-member`）。候補が無ければ `candidate-not-found`
 * - 自分の投稿は報告できない（`cannot-report-own-candidate`）
 * - 1 人 1 候補につき 1 回（ID をルーム・候補・報告した人から決める）。2 回目は何も作らずに `alreadyReported: true` を返す
 *   （アプリはどちらでもひとこととURLを隠す。別の端末から報告し直したときも同じ）
 * - ルームの状態は問わない（`drawn`・`closed` でも報告できる）
 * 報告した人の画面でひとこととURLを隠すのはアプリ（端末に覚える）。`reports`・`mail` はクライアントから読めない。
 * @param deps 外部のもの
 * @param uid 報告する人
 * @param data `request.data`（`{ roomId, candidateId, reason }`）
 * @param mail メールの送り先
 * @returns 結果
 */
export async function reportCandidate(
  deps: ServiceDeps,
  uid: string,
  data: unknown,
  mail: ReportMailSettings,
): Promise<ReportCandidateResult> {
  const input = parseReportCandidateInput(data);
  const { db } = deps;
  const ref = roomRef(db, input.roomId);
  const reportId = reportDocumentId(input.roomId, input.candidateId, uid);
  return db.runTransaction(async (tx) => {
    const { room } = await getRoomAsMember(tx, ref, uid);
    const candidate = (await tx.get(candidatesRef(ref).doc(input.candidateId))).data() as CandidateDoc | undefined;
    if (candidate === undefined) {
      throw appError("candidate-not-found");
    }
    const report = await tx.get(reportRef(db, reportId));
    const decision = decideReport(candidate, uid, report.exists);
    if (decision.kind === "already-reported") {
      return { alreadyReported: true, mailQueued: false };
    }
    const snapshot = snapshotOf(candidate);
    const doc: Omit<ReportDoc, "createdAt"> & { createdAt: FieldValue } = {
      roomId: input.roomId,
      candidateId: input.candidateId,
      reporterId: uid,
      reason: input.reason,
      createdAt: FieldValue.serverTimestamp(),
      candidate: snapshot,
    };
    tx.create(reportRef(db, reportId), doc);
    const message = reportMailOf(mail.to, {
      reportId,
      roomId: input.roomId,
      roomName: room.name,
      candidateId: input.candidateId,
      reason: input.reason,
      candidate: snapshot,
      reportedAtMs: deps.nowMs(),
    });
    if (message !== null) {
      tx.create(mailRef(db, reportId), message);
    }
    return { alreadyReported: false, mailQueued: message !== null };
  });
}
