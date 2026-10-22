/**
 * Emulator の Firestore に Admin SDK（ルールを通らない）で繋ぐ道具。
 * Functions の処理（`functions/src/rooms/service.ts` など）を、乱数を差し替えて直接呼ぶテストで使う。
 */
import { deleteApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import { PROJECT_ID, requireEnv } from "./env";

/**
 * Admin SDK のアプリを作る。接続先は emulators:exec が渡す FIRESTORE_EMULATOR_HOST（Admin SDK が自分で読む）。
 * @param name アプリの名前（テストのファイルごとに分ける）
 */
export function openAdmin(name: string): { app: App; db: Firestore } {
  requireEnv("FIRESTORE_EMULATOR_HOST");
  const app = initializeApp({ projectId: PROJECT_ID }, name);
  return { app, db: getFirestore(app) };
}

/** Admin SDK のアプリを閉じる */
export async function closeAdmin(app: App): Promise<void> {
  await deleteApp(app);
}

/** データを消すのをやり直す最大の回数（トリガーのトランザクションと重なったとき） */
const CLEAR_ATTEMPTS = 10;
/** データを消すのをやり直すまでの間隔 */
const CLEAR_RETRY_INTERVAL_MS = 500;

/**
 * `clear` を、トランザクションのロックと重なって失敗（409 ABORTED「Transaction lock timeout」）したらやり直す。
 * Functions の Emulator のトリガー（onMemberWrite など）は、前のテストの書き込みで遅れて動き、トランザクションで
 * ルームとメンバーを読んでいる間はロックを持つ。そこへデータを消すと、ロックを待ちきれずに 409 で失敗する。
 * やり直すまでの間にトリガーが終わる（ルームが消えていれば何も書かない）ので、間隔を空けて上限の回数までやり直す。
 * @param clear データを消す処理（409 で失敗したら、`isAborted` が true を返すエラーを投げる）
 * @param isAborted エラーがロックの待ちきれない失敗か
 */
export async function retryWhileLocked(clear: () => Promise<void>, isAborted: (error: unknown) => boolean): Promise<void> {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await clear();
      return;
    } catch (error) {
      if (attempt >= CLEAR_ATTEMPTS || !isAborted(error)) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, CLEAR_RETRY_INTERVAL_MS));
    }
  }
}

/** ロックを待ちきれずに失敗したエラー（Firestore の Emulator の 409 ABORTED）か */
export function isLockTimeout(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("409") || message.includes("ABORTED");
}

/** Emulator の Firestore のデータをすべて消す（トリガーのトランザクションと重なったらやり直す） */
export async function clearFirestore(): Promise<void> {
  const host = requireEnv("FIRESTORE_EMULATOR_HOST");
  await retryWhileLocked(async () => {
    const response = await fetch(
      `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
      { method: "DELETE" },
    );
    if (!response.ok) {
      throw new Error(`Firestore のデータを消せませんでした: ${String(response.status)}`);
    }
  }, isLockTimeout);
}
