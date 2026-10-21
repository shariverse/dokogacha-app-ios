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

/** Emulator の Firestore のデータをすべて消す */
export async function clearFirestore(): Promise<void> {
  const host = requireEnv("FIRESTORE_EMULATOR_HOST");
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Firestore のデータを消せませんでした: ${String(response.status)}`);
  }
}
