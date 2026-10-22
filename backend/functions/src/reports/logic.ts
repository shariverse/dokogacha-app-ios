/**
 * 投稿の報告（02 の §3.5・F-14）の判定と、運営に送るメールの組み立て（Firestore に触れない純粋な関数）。
 * Firestore の読み書きは `service.ts` が行う。報告できるかの判定は、アプリの `CandidatePermission.canReport`
 * （と擬似のサーバー `InMemoryServer+Report.swift`）と同じ規則・同じケースで確かめる。
 */
import { createHash } from "node:crypto";

import type { CandidateDoc, ReportedCandidateSnapshot, ReportReason } from "../domain/models";
import { appError } from "../errors";

/** 報告の理由の、運営に送るメールに書く表示名（02 の §3.5「不適切な内容／スパム／その他」） */
export const REPORT_REASON_LABELS: Readonly<Record<ReportReason, string>> = {
  inappropriate: "不適切な内容",
  spam: "スパム",
  other: "その他",
};

/**
 * 候補を報告できるか（02 の §3.5・03 の S-10「他人の投稿なら『この投稿を報告』」）。自分の投稿は報告できない。
 * ルームの状態は問わない（終了したルームの投稿も、不適切なら運営が確かめられるようにする）。
 * Swift 側の `CandidatePermission.canReport` と同じ規則。
 * @param postedBy 候補を投稿した人の uid
 * @param uid 報告する人の uid
 */
export function canReport(postedBy: string, uid: string): boolean {
  return postedBy !== uid;
}

/** `reportCandidate` の判定の結果 */
export type ReportDecision =
  /** 報告を作る */
  | { kind: "create" }
  /** 同じ人がこの候補をもう報告している（作らずに成功を返す。1 人 1 候補につき 1 回） */
  | { kind: "already-reported" };

/**
 * 報告してよいか判定する。呼んだ人がメンバーで、候補があることは、呼ぶ側で確かめておく。
 * 1. 自分の投稿 → `cannot-report-own-candidate`
 * 2. もう報告している → `already-reported`（二重に保存せず、メールも送り直さない）
 * 3. 報告を作る
 * @param candidate 報告する候補
 * @param uid 報告する人
 * @param alreadyReported この人がこの候補の報告をもう持っているか
 * @throws `cannot-report-own-candidate`
 */
export function decideReport(candidate: Pick<CandidateDoc, "postedBy">, uid: string, alreadyReported: boolean): ReportDecision {
  if (!canReport(candidate.postedBy, uid)) {
    throw appError("cannot-report-own-candidate");
  }
  return alreadyReported ? { kind: "already-reported" } : { kind: "create" };
}

/**
 * 報告のドキュメントの ID（ルーム・候補・報告した人から決まる。1 人 1 候補につき 1 つにするため）。
 * ID は入力の文字列なので、つないだだけだと区切りの文字を含む ID どうしで重なりうる。JSON の配列にしてから SHA-256 にする。
 * 運営に送るメールの ID（`mail/{id}`）にも同じ値を使い、メールも 1 通だけにする。
 */
export function reportDocumentId(roomId: string, candidateId: string, reporterId: string): string {
  return createHash("sha256").update(JSON.stringify([roomId, candidateId, reporterId])).digest("hex");
}

/**
 * 報告した時点の候補の内容（`reports.candidate`）。表示名（`postedByName`）といいねした人は持たない。
 * @param candidate 報告された候補
 */
export function snapshotOf(candidate: CandidateDoc): ReportedCandidateSnapshot {
  return {
    placeName: candidate.place.name,
    area: candidate.place.area,
    category: candidate.category,
    note: candidate.note,
    url: candidate.url ?? null,
    postedBy: candidate.postedBy,
  };
}

/** Trigger Email 拡張（firestore-send-email）の `mail` のドキュメント（拡張の `to`・`message` の形） */
export interface ReportMailDoc {
  /** 宛先（Functions のパラメータ `REPORT_MAIL_TO`。値はリポジトリに書かない） */
  to: string;
  /** 件名と本文（本文はテキストだけ。投稿の内容を HTML として解釈させない） */
  message: { subject: string; text: string };
}

/** メールに書く報告の内容 */
export interface ReportMailContent {
  /** 報告の ID（`reports/{id}`。運営がコンソールで引く） */
  reportId: string;
  /** ルームの ID */
  roomId: string;
  /** ルーム名 */
  roomName: string;
  /** 候補の ID */
  candidateId: string;
  /** 理由 */
  reason: ReportReason;
  /** 報告した時点の候補の内容 */
  candidate: ReportedCandidateSnapshot;
  /** 報告した日時（UNIX 時刻のミリ秒。サーバーの時刻） */
  reportedAtMs: number;
}

/**
 * 運営に送るメール（`mail/{reportId}`）を組み立てる。宛先が空（パラメータを入れ忘れた）なら null（報告は保存し、メールは書かない）。
 * 個人情報は最小限にする: 報告した人の uid と、表示名（投稿した人・報告した人）は書かない。投稿した人は uid だけ（運営が対応に使う）。
 * 件名には利用者の入力を入れない（理由の表示名だけ）。
 * @param to 宛先
 * @param content 報告の内容
 */
export function reportMailOf(to: string, content: ReportMailContent): ReportMailDoc | null {
  const recipient = to.trim();
  if (recipient === "") {
    return null;
  }
  const reason = REPORT_REASON_LABELS[content.reason];
  const { candidate } = content;
  const lines = [
    "ドコガチャで投稿の報告がありました。内容を確認し、必要なら Firebase のコンソールで候補を削除してください。",
    "",
    `理由: ${reason}`,
    `報告の日時: ${new Date(content.reportedAtMs).toISOString()}`,
    `報告の ID: ${content.reportId}`,
    "",
    `ルーム: ${content.roomName}`,
    `ルームの ID: ${content.roomId}`,
    `候補の ID: ${content.candidateId}`,
    `場所: ${candidate.placeName}${candidate.area === "" ? "" : `（${candidate.area}）`}`,
    `カテゴリ: ${candidate.category}`,
    `ひとこと: ${candidate.note === "" ? "（なし）" : candidate.note}`,
    `参考URL: ${candidate.url ?? "（なし）"}`,
    `投稿した人のユーザー ID: ${candidate.postedBy}`,
  ];
  return {
    to: recipient,
    message: { subject: `【ドコガチャ】投稿の報告（${reason}）`, text: `${lines.join("\n")}\n` },
  };
}
