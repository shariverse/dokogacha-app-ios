/**
 * Callable Functions が返すエラーと、アプリに出す文言の対応（この 1 か所にまとめる）。
 *
 * - アプリは `HttpsError` の `details.reason`（下の `AppErrorReason`）で文言を選ぶ。`code` は gRPC の分類で、
 *   再試行してよいか（`unavailable`）などの判断に使う。同じ `code` に別の理由が複数あるため、文言は `reason` で引く
 * - `message` にもアプリの文言を入れる（ログで読めるように。アプリはローカライズのため自分の文言の表を持つ。タスク 11）
 * - 文言は 02・03 にあればその表記どおり（F-04 の AC など）。無いものはこのファイルで決める
 * - 想定していない例外は `internal`（「通信できませんでした」）にする（`callable.ts`）
 */
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import { MAX_CANDIDATES, MAX_MEMBERS } from "./domain/constants";

/** エラーの理由ごとの、gRPC のコードとアプリの文言 */
export const APP_ERRORS = {
  /** サインインしていない（匿名認証の前に呼んだ） */
  unauthenticated: { code: "unauthenticated", message: "通信できませんでした" },
  /** 入力の形が正しくない（アプリが検証してから呼ぶので、通常は出ない） */
  "invalid-argument": { code: "invalid-argument", message: "入力内容を確認してください" },
  /** 表示名を登録する前に、ルームを作成・参加しようとした（S-01 を通っていない） */
  "profile-required": { code: "failed-precondition", message: "表示名を登録してください" },
  /** 招待コードが存在しない・形が正しくない（02 の F-04 の AC） */
  "invite-code-not-found": { code: "not-found", message: "招待コードが見つかりません" },
  /** メンバーが上限に達している（02 の F-04 の AC） */
  "room-full": { code: "resource-exhausted", message: `このルームは満員です（最大${String(MAX_MEMBERS)}人）` },
  /**
   * ルームが `drawn`・`closed` で参加できない（02 の F-04 の AC）。
   * 候補の追加・削除（02 の §2.1「投稿・削除は open・unlocked のときだけ」）・強制解禁（02 の F-32「未解禁のとき」）を
   * `drawn`・`closed` で呼んだときにも使う
   */
  "room-already-decided": { code: "failed-precondition", message: "このルームはもう行き先が決まっています" },
  /** ルームが存在しない */
  "room-not-found": { code: "not-found", message: "ルームが見つかりません" },
  /** ルームのメンバーではない */
  "not-room-member": { code: "permission-denied", message: "このルームのメンバーではありません" },
  /** 作成者だけができる操作を、作成者以外が呼んだ */
  "not-room-owner": { code: "permission-denied", message: "作成者だけが操作できます" },
  /** 作成者は退出できない（02 の F-05「作成者は退出できない（MVP）」） */
  "owner-cannot-leave": { code: "failed-precondition", message: "作成者はルームから退出できません" },
  /** 作成者を削除しようとした（作成者は退出できないので、削除もできない） */
  "cannot-remove-owner": { code: "failed-precondition", message: "作成者は削除できません" },
  /** 削除しようとした人が、もうメンバーにいない */
  "member-not-found": { code: "not-found", message: "このメンバーはもうルームにいません" },
  /** 自分の投稿数がルームの上限（`settings.postLimit`）に達している（02 の F-10 の「上限」） */
  "post-limit-reached": { code: "resource-exhausted", message: "投稿できる数の上限に達しています" },
  /** ルームの候補が上限（02 の §9「最大200件」）に達している（退出した人の候補が残ると、投稿数の上限の合計を超えうる） */
  "room-candidates-full": {
    code: "resource-exhausted",
    message: `このルームの候補は上限に達しています（最大${String(MAX_CANDIDATES)}件）`,
  },
  /** 候補が存在しない（ほかの人がすでに削除した） */
  "candidate-not-found": { code: "not-found", message: "候補が見つかりません" },
  /** 投稿した人と作成者以外が候補を削除しようとした（02 の F-11） */
  "not-candidate-owner": { code: "permission-denied", message: "投稿した人と作成者だけが削除できます" },
  /**
   * ルームが `closed` で設定を変えられない（02 の F-03「ルーム名 いつでも変更可（closed 以外）」。
   * 終了したルームは閲覧のみ（02 の §2.1）なので、ほかの項目も変えられない）
   */
  "room-closed": { code: "failed-precondition", message: "このルームは終了しています" },
  /** 投稿数を今より少なくしようとした（02 の F-03「引き上げのみ可（下げられない）」） */
  "post-limit-decrease": { code: "failed-precondition", message: "投稿数は今より少なくできません" },
  /** `open` 以外で解禁の条件（締切日時を含む）を変えようとした（02 の F-03「open のときのみ変更可」） */
  "unlock-rule-locked": { code: "failed-precondition", message: "解禁の条件は候補募集中のときだけ変更できます" },
  /** `drawn`・`closed` でいいねの効き方を変えようとした（02 の F-03「open/unlocked のときのみ変更可」） */
  "like-mode-locked": { code: "failed-precondition", message: "行き先が決まった後は、いいねの効き方を変更できません" },
  /**
   * ガチャを回そうとしたが、ルームが解禁されていない（02 の F-40「unlocked のとき、メンバーなら誰でも回せる」）。
   * `status` が `unlocked` でも、`drawGacha` が数え直した準備OKで解禁の条件を満たさないとき（参加した直後で、
   * `onMemberWrite` がまだ `open` に戻していない間）にも使う
   */
  "room-not-unlocked": { code: "failed-precondition", message: "まだガチャは解禁されていません" },
  /** 抽選の対象の候補が無い（02 の F-40「候補が0件のときは回せない（「候補がありません」）」。引き直しで全部除外したときも） */
  "no-candidates": { code: "failed-precondition", message: "候補がありません" },
  /**
   * ガチャで当選した候補（今の当選・引き直しで除外した前の当選）を削除しようとした。
   * 抽選の記録（`draws`）と行き先きっぷ・過去のアイデアが指す候補が消えないようにする
   */
  "candidate-drawn": { code: "failed-precondition", message: "ガチャで当選した候補は削除できません" },
  /**
   * 行き先が決まる前（`open`・`unlocked`）に、引き直しを提案した（02 の §6.4「drawn のとき、メンバーの誰かが提案」）か、
   * 「この行き先で決定」（`closeRoom`）を呼んだ（02 の §6.5「drawn → closed」）
   */
  "room-not-drawn": { code: "failed-precondition", message: "まだ行き先が決まっていません" },
  /**
   * 引き直しの権利を使った後に、もう一度提案した（02 の §6.4「ルームにつき1回まで」「否決後は再提案できない」・
   * F-43 の AC「引き直しは2回目を提案できない」）。文言は 02 の §6.4 の「使用済み」の表示
   */
  "reroll-used": { code: "failed-precondition", message: "引き直しは使用済みです" },
  /** 投票中でない（提案されていない・可決・否決の後）引き直しに投票した */
  "reroll-not-voting": { code: "failed-precondition", message: "引き直しの投票は終わっています" },
  /**
   * 自分の投稿を報告しようとした（02 の §3.5・03 の S-10「他人の投稿なら『この投稿を報告』」。アプリは自分の投稿にメニューを出さないので、通常は出ない）
   */
  "cannot-report-own-candidate": { code: "failed-precondition", message: "自分の投稿は報告できません" },
  /**
   * 広告非表示の購入（02 の F-51）を確かめられなかった。署名付きトランザクションの検証に失敗した・別のアプリや別のアイテムのもの・
   * 返金などで取り消されたもの（`verifyPurchase`）。文言は 02・03 に無いのでここで決めた
   */
  "purchase-invalid": { code: "failed-precondition", message: "購入を確認できませんでした" },
  /** 購入の検証が一時的にできなかった（証明書の失効の確認に通信できなかったなど。もう一度で通る見込みがある） */
  "purchase-verification-unavailable": { code: "unavailable", message: "通信できませんでした" },
  /** 招待コードを決められなかった（重複が続いた。もう一度呼べば通る見込みが高い） */
  "invite-code-unavailable": { code: "unavailable", message: "通信できませんでした" },
  /** 想定していないエラー */
  internal: { code: "internal", message: "通信できませんでした" },
} as const satisfies Record<string, { code: FunctionsErrorCode; message: string }>;

/** エラーの理由（`HttpsError` の `details.reason` の値） */
export type AppErrorReason = keyof typeof APP_ERRORS;

/** `HttpsError` の `details` の形 */
export interface AppErrorDetails {
  /** エラーの理由 */
  reason: AppErrorReason;
}

/**
 * 理由に対応する `HttpsError` を作る。Callable の中で `throw appError("room-full")` のように使う。
 * @param reason エラーの理由
 * @returns アプリに返すエラー
 */
export function appError(reason: AppErrorReason): HttpsError {
  const { code, message } = APP_ERRORS[reason];
  const details: AppErrorDetails = { reason };
  return new HttpsError(code, message, details);
}
