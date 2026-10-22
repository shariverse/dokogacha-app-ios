/**
 * Emulator のテストで使う接続先と期待値。
 * 接続先は emulators:exec が渡す環境変数から読む（DG_EMULATOR_PORT_OFFSET でずらしたポートがそのまま入る）。
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";

/** Emulator のプロジェクト ID（demo- で始まるので実プロジェクトには接続しない） */
export const PROJECT_ID = "demo-dokogacha";

/** backend/ の絶対パス */
export const BACKEND_DIR = join(__dirname, "..", "..");

/**
 * 必須の環境変数を読む。無ければ、emulators:exec の外で流したと分かるメッセージで失敗する。
 */
export function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(`${name} がありません。npm run test:emulator から流してください`);
  }
  return value;
}

/**
 * "host:port" を分ける。
 */
export function parseHostPort(value: string): { host: string; port: number } {
  const index = value.lastIndexOf(":");
  if (index < 0) {
    throw new Error(`host:port の形ではありません: ${value}`);
  }
  return { host: value.slice(0, index), port: Number(value.slice(index + 1)) };
}

/** firebase.json の emulators の設定（ずらす前） */
interface EmulatorsConfig {
  emulators: Record<string, { port?: number }>;
}

/**
 * firebase.json に書いた Emulator のポートに、DG_EMULATOR_PORT_OFFSET を足した値を返す。
 */
export function expectedPort(emulator: string): number {
  const config = JSON.parse(readFileSync(join(BACKEND_DIR, "firebase.json"), "utf8")) as EmulatorsConfig;
  const base = config.emulators[emulator]?.port;
  if (base === undefined) {
    throw new Error(`firebase.json に ${emulator} のポートがありません`);
  }
  return base + Number(process.env.DG_EMULATOR_PORT_OFFSET ?? "0");
}
