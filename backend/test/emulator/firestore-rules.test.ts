/**
 * Firestore のセキュリティルールのテスト。
 * いまのルールはすべての読み書きを拒否する。コレクションごとの許可を足すタスクで、ここにケースを足していく。
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  assertFails,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

import { BACKEND_DIR, parseHostPort, PROJECT_ID, requireEnv } from "./env";

describe("firestore.rules（すべて拒否）", () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    // emulators:exec が渡す接続先を使う（DG_EMULATOR_PORT_OFFSET でずらしたポート）
    const { host, port } = parseHostPort(requireEnv("FIRESTORE_EMULATOR_HOST"));
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        host,
        port,
        rules: readFileSync(join(BACKEND_DIR, "firestore.rules"), "utf8"),
      },
    });
  });

  afterEach(async () => {
    await testEnv.clearFirestore();
  });

  afterAll(async () => {
    await testEnv.cleanup();
  });

  it("ログインしていない人は読めない", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "rooms/room1")));
  });

  it("ログインしている人も自分のユーザーを読めない", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await assertFails(getDoc(doc(db, "users/alice")));
  });

  it("ログインしている人も書けない", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await assertFails(setDoc(doc(db, "rooms/room1"), { name: "テスト" }));
  });

  it("サブコレクションも書けない", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await assertFails(setDoc(doc(db, "rooms/room1/members/alice"), { ready: true }));
  });
});
