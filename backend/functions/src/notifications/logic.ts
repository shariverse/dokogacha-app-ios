/**
 * プッシュ通知（02 の §8 F-60）の文面・宛先・ペイロードを決める純粋な関数（Firestore と FCM に触れない）。
 * Firestore を読むのと FCM に送るのは `service.ts`・`sender.ts` が行い、「何を誰に送るか」はここで決めて Jest で確かめる。
 *
 * ペイロード（`data`）の形はアプリの `PushDestination`（`Dokogacha/Domain/Logic/PushDestination.swift`）が読む。
 * 片方を変えたら両方を変える。
 */

/** 通知の種類（ペイロードの `type`） */
export const PUSH_EVENT_KINDS = ["unlocked", "drawn", "rerollProposed"] as const;
/** 通知の種類 */
export type PushEventKind = (typeof PUSH_EVENT_KINDS)[number];

/** 通知を開いたときの行き先（05 の §7「通知のペイロードに roomId と遷移先（room / result）を入れる」） */
export type PushTarget = "room" | "result";

/** 送る出来事（ルームの値を読んだ後の、文面と宛先を決めるのに要る値） */
export type PushEvent =
  /** ガチャが解禁された（宛先は全メンバー） */
  | { kind: "unlocked"; roomId: string; roomName: string }
  /** 行き先が決まった（宛先は回した人以外） */
  | { kind: "drawn"; roomId: string; roomName: string; drawId: string; drawnBy: string }
  /** 引き直しが提案された（宛先は提案者以外。`drawId` は提案した時点の抽選） */
  | { kind: "rerollProposed"; roomId: string; drawId: string | null; proposedBy: string; proposerName: string };

/** 送る相手のトークン 1 つ */
export interface PushRecipient {
  /** トークンの持ち主の uid（無効なトークンを消すときに使う） */
  uid: string;
  /** FCM の登録トークン */
  token: string;
}

/** 宛先を決めるのに使うユーザー（`users/{uid}` の `fcmTokens`。ドキュメントが無ければ `fcmTokens` は undefined） */
export interface RecipientUser {
  /** uid */
  uid: string;
  /** 通知のトークン（壊れた値も来うるので unknown で受ける） */
  fcmTokens: unknown;
}

/** 1 人から読むトークンの上限（セキュリティルールの `maxFcmTokens()` と同じ。壊れたデータで送る数を増やさない） */
export const MAX_TOKENS_PER_USER = 10;
/** トークンの最大の長さ（セキュリティルールの `validFcmTokenAt` と同じ） */
export const MAX_TOKEN_LENGTH = 4096;

/**
 * 通知の本文（02 の §8 の表の文面そのまま。タイトルは付けない（端末がアプリ名を出す））。
 * @param event 送る出来事
 */
export function pushBody(event: PushEvent): string {
  switch (event.kind) {
    case "unlocked":
      return `「${event.roomName}」のガチャが解禁されました！`;
    case "drawn":
      return `「${event.roomName}」の行き先が決まりました`;
    case "rerollProposed":
      return `${event.proposerName}さんが引き直しを提案しています`;
  }
}

/**
 * 通知を開いたときの行き先（02 の §8「通知をタップすると該当ルーム（結果があれば結果画面）を開く」）。
 * 解禁はルーム（S-07）、抽選結果と引き直しの提案は結果（S-14。提案への投票は S-14 にある）
 * @param event 送る出来事
 */
export function pushTarget(event: PushEvent): PushTarget {
  return event.kind === "unlocked" ? "room" : "result";
}

/**
 * 宛先から外す人（02 の §8 の「宛先」。解禁は全メンバーなので誰も外さない）
 * @param event 送る出来事
 */
export function excludedRecipient(event: PushEvent): string | null {
  switch (event.kind) {
    case "unlocked":
      return null;
    case "drawn":
      return event.drawnBy;
    case "rerollProposed":
      return event.proposedBy;
  }
}

/**
 * 通知のペイロード（FCM の `data`。値はすべて文字列）。アプリはこれで開く画面を決める。
 * - `type`: 通知の種類（前面にいるときに出すかを決めるのに使う）
 * - `roomId`: ルームの ID
 * - `target`: `room`（S-07）か `result`（S-14）
 * - `drawId`: 結果を開くときの抽選の ID（あれば）
 * @param event 送る出来事
 */
export function pushData(event: PushEvent): Record<string, string> {
  const data: Record<string, string> = { type: event.kind, roomId: event.roomId, target: pushTarget(event) };
  const drawId = event.kind === "unlocked" ? null : event.drawId;
  if (drawId !== null && drawId !== "") {
    data.drawId = drawId;
  }
  return data;
}

/**
 * 同じ通知を 2 回送らないための印のキー（`rooms/{roomId}/notificationLog/{key}` を作れた 1 回だけ送る）。
 * - 解禁: ルームにつき 1 回（準備OKの付け外しで `open`⇄`unlocked` を繰り返しても、2 回目からは送らない）
 * - 抽選結果: 抽選ごとに 1 回（`onRoomDrawn` のやり直し（`retry`）で 2 回送らない。引き直しの後の抽選は別の ID なので送る）
 * - 引き直しの提案: ルームにつき 1 回（提案はルームにつき 1 回だけ。02 の §6.4）
 * @param event 送る出来事
 */
export function notificationLogKey(event: PushEvent): string {
  switch (event.kind) {
    case "unlocked":
      return "unlocked";
    case "drawn":
      return `drawn-${event.drawId}`;
    case "rerollProposed":
      return "rerollProposed";
  }
}

/**
 * ユーザーのドキュメントから、送ってよいトークンを取り出す（空でない・長すぎない文字列だけ。上限の数まで）。
 * @param fcmTokens `users/{uid}.fcmTokens` の値
 */
export function validTokensOf(fcmTokens: unknown): string[] {
  if (!Array.isArray(fcmTokens)) {
    return [];
  }
  return fcmTokens
    .filter((token): token is string => typeof token === "string" && token.length > 0 && token.length <= MAX_TOKEN_LENGTH)
    .slice(0, MAX_TOKENS_PER_USER);
}

/**
 * 宛先のトークンを決める。
 * - ルームのメンバー（`memberIds`）だけ。退出した人・メンバーでないユーザーは、`users` に入っていても送らない
 * - `excluded`（回した人・提案した人）を外す
 * - トークンの無い人（通知を許可していない・まだ登録していない・ドキュメントが無い）は外す
 * - 同じトークンは 1 回だけ（2 人のドキュメントに同じ端末のトークンが残っていても、端末に 2 通届かないように。持ち主は先に見つけた人）
 *
 * 通知の受け取りを切る設定はアプリに無い（05 の §3 の `users` に無い）。iOS の設定で通知を切った端末には、送っても表示されない。
 * @param memberIds ルームのメンバーの uid（`rooms.memberIds`）
 * @param excluded 外す人の uid（無ければ null）
 * @param users メンバーのユーザー
 */
export function selectRecipients(memberIds: readonly string[], excluded: string | null, users: readonly RecipientUser[]): PushRecipient[] {
  const members = new Set(memberIds);
  const seen = new Set<string>();
  const recipients: PushRecipient[] = [];
  for (const user of users) {
    if (!members.has(user.uid) || user.uid === excluded) {
      continue;
    }
    for (const token of validTokensOf(user.fcmTokens)) {
      if (seen.has(token)) {
        continue;
      }
      seen.add(token);
      recipients.push({ uid: user.uid, token });
    }
  }
  return recipients;
}

/** 送った結果 1 つ（FCM の `SendResponse` から取り出したもの） */
export interface PushSendResult {
  /** 送れたか */
  success: boolean;
  /** 失敗したときのエラーコード（`messaging/registration-token-not-registered` など） */
  errorCode?: string;
}

/**
 * トークンがもう使えないことを示すエラーコード（アプリを消した・トークンが替わった・形が正しくない）。
 * これらのトークンは `users.fcmTokens` から外す。通信の失敗・FCM の障害（`messaging/internal-error` など）では外さない
 */
export const UNREGISTERED_TOKEN_ERROR_CODES: readonly string[] = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
];

/**
 * 送った結果から、外すトークンを持ち主ごとにまとめる。
 * @param recipients 送った相手（`results` と同じ順）
 * @param results 送った結果
 * @returns uid → 外すトークン（外すものが無い人は入らない）
 */
export function unregisteredTokensByUser(
  recipients: readonly PushRecipient[],
  results: readonly PushSendResult[],
): Map<string, string[]> {
  const byUser = new Map<string, string[]>();
  recipients.forEach((recipient, index) => {
    const result = results[index];
    if (result === undefined || result.success || !UNREGISTERED_TOKEN_ERROR_CODES.includes(result.errorCode ?? "")) {
      return;
    }
    byUser.set(recipient.uid, [...(byUser.get(recipient.uid) ?? []), recipient.token]);
  });
  return byUser;
}
