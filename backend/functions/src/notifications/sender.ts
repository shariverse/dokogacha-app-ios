/**
 * プッシュ通知を送る部分（FCM。firebase-admin の messaging）。
 *
 * Emulator には FCM が無く、実際には送れない。Emulator（Functions の Emulator と、Emulator に繋いだテスト）では
 * FCM に送る代わりに Firestore の `emulatorPushOutbox` に書き、テストが「何を誰に送ったか」を読めるようにする。
 * どちらで送るかは `defaultPushSender` が環境変数で決める（本番の Functions には Emulator の環境変数が無い）。
 */
import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { getMessaging, type Message } from "firebase-admin/messaging";

import type { PushSendResult } from "./logic";

/** 送る通知 1 通（トークン 1 つ分） */
export interface PushMessage {
  /** FCM の登録トークン */
  token: string;
  /** 本文 */
  body: string;
  /** ペイロード（`pushData`） */
  data: Record<string, string>;
  /** 通知センターでまとめる単位（ルームの ID） */
  threadId: string;
}

/** 通知を送る。結果は `messages` と同じ順で返す */
export type PushSender = (messages: readonly PushMessage[]) => Promise<PushSendResult[]>;

/** FCM の `sendEach` に一度に渡せる数の上限 */
export const FCM_BATCH_LIMIT = 500;

/** Emulator で、送った通知を書くコレクション（クライアントからは読めない。ルールの最後の match で拒否） */
export const EMULATOR_OUTBOX_COLLECTION = "emulatorPushOutbox";

/** Emulator で、このトークンの頭で始まるものは「登録されていない」として失敗させる（無効なトークンを外すテスト用） */
export const EMULATOR_UNREGISTERED_TOKEN_PREFIX = "emulator-unregistered-";

/**
 * FCM に渡す形にする（APNs の通知として、本文と既定の音を付ける。ペイロードは `data` に入れる）。
 * @param message 送る通知
 */
export function toFcmMessage(message: PushMessage): Message {
  return {
    token: message.token,
    notification: { body: message.body },
    data: message.data,
    apns: { payload: { aps: { sound: "default", threadId: message.threadId } } },
  };
}

/**
 * FCM で送る（本番）。上限の数ずつ `sendEach` に渡す。
 * @returns 送る関数
 */
export function fcmSender(): PushSender {
  return async (messages) => {
    const results: PushSendResult[] = [];
    for (let start = 0; start < messages.length; start += FCM_BATCH_LIMIT) {
      const batch = messages.slice(start, start + FCM_BATCH_LIMIT).map(toFcmMessage);
      const response = await getMessaging().sendEach(batch);
      for (const item of response.responses) {
        results.push(item.success ? { success: true } : { success: false, errorCode: item.error?.code ?? "unknown" });
      }
    }
    return results;
  };
}

/**
 * Emulator で送ったことにする（`emulatorPushOutbox` に 1 通ずつ書く）。
 * トークンが `EMULATOR_UNREGISTERED_TOKEN_PREFIX` で始まるときは書かずに「登録されていない」で失敗させる。
 * @param db 書く Firestore
 * @returns 送る関数
 */
export function emulatorOutboxSender(db: Firestore): PushSender {
  return async (messages) => {
    const outbox = db.collection(EMULATOR_OUTBOX_COLLECTION);
    return Promise.all(
      messages.map(async (message): Promise<PushSendResult> => {
        if (message.token.startsWith(EMULATOR_UNREGISTERED_TOKEN_PREFIX)) {
          return { success: false, errorCode: "messaging/registration-token-not-registered" };
        }
        await outbox.add({ ...message, createdAt: FieldValue.serverTimestamp() });
        return { success: true };
      }),
    );
  };
}

/**
 * Emulator で動いているか（Functions の Emulator が `FUNCTIONS_EMULATOR`、Emulator に繋いだテストが `FIRESTORE_EMULATOR_HOST` を持つ）。
 * @param env 環境変数
 */
export function isEmulatorEnvironment(env: NodeJS.ProcessEnv): boolean {
  return env.FUNCTIONS_EMULATOR === "true" || (env.FIRESTORE_EMULATOR_HOST ?? "") !== "";
}

/**
 * 既定の送り方（Emulator なら `emulatorPushOutbox` に書く。本番は FCM）。
 * @param db Emulator のときに書く Firestore
 * @param env 環境変数
 */
export function defaultPushSender(db: Firestore, env: NodeJS.ProcessEnv = process.env): PushSender {
  return isEmulatorEnvironment(env) ? emulatorOutboxSender(db) : fcmSender();
}
