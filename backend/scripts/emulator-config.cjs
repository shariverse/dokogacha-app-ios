#!/usr/bin/env node
// firebase.json の Emulator のポートに DG_EMULATOR_PORT_OFFSET（既定 0）を足した設定ファイルを書き出し、そのパスを出力する。
// 2 つの作業スロットで同時に Emulator を起動してもポートがぶつからないようにするため（スロット a は 0、b は 100）。
// Emulator で動かせない拡張（extensions）は外す（withoutExtensions）。
// 書き出すファイルは firebase.json と同じディレクトリに置く（rules・functions・hosting の相対パスをそのまま使うため）。git の管理外。
"use strict";

const { readFileSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");

/** 書き出す設定ファイルの名前（.gitignore に入れてある） */
const GENERATED_CONFIG_NAME = "firebase.emulators.local.json";

/** Emulator の設定のうち、ずらす対象のキー（Firestore の websocketPort も別のポートを開く） */
const PORT_KEYS = /** @type {const} */ (["port", "websocketPort"]);

/**
 * 環境変数の値をポートのずらし幅として読む。空なら 0。
 * @param {string | undefined} raw
 * @returns {number}
 */
function parseOffset(raw) {
  if (raw === undefined || raw === "") {
    return 0;
  }
  if (!/^\d+$/.test(raw)) {
    throw new Error(`DG_EMULATOR_PORT_OFFSET は 0 以上の整数で指定してください（指定された値: ${raw}）`);
  }
  return Number(raw);
}

/**
 * Emulator の設定から、ポートの一覧を「Emulator 名.キー」ごとに取り出す。
 * @param {Record<string, unknown>} emulators firebase.json の emulators
 * @returns {Map<string, number>}
 */
function collectPorts(emulators) {
  /** @type {Map<string, number>} */
  const ports = new Map();
  for (const [name, value] of Object.entries(emulators)) {
    if (typeof value !== "object" || value === null) {
      continue;
    }
    const settings = /** @type {Record<string, unknown>} */ (value);
    for (const key of PORT_KEYS) {
      const port = settings[key];
      if (typeof port === "number") {
        ports.set(`${name}.${key}`, port);
      }
    }
  }
  return ports;
}

/**
 * firebase.json の内容から、Emulator のポートをずらした設定を作る。元のオブジェクトは変えない。
 * ずらした後のポートが、ずらす前（ずらし 0 のスロット）のどれかと重なるときは失敗する
 * （例: hub 4400 を 100 ずらすと、ずらし 0 の logging が 4500 なら同時に起動できない）。
 * @param {Record<string, unknown>} config firebase.json の内容
 * @param {number} offset 各ポートに足す値
 * @returns {Record<string, unknown>}
 */
function shiftEmulatorPorts(config, offset) {
  const shifted = structuredClone(config);
  const emulators = shifted.emulators;
  if (typeof emulators !== "object" || emulators === null) {
    throw new Error("firebase.json に emulators の設定がありません");
  }
  const emulatorSettings = /** @type {Record<string, Record<string, unknown>>} */ (emulators);
  const basePorts = collectPorts(emulatorSettings);
  /** @type {Map<number, string>} */
  const baseOwners = new Map([...basePorts].map(([owner, port]) => [port, owner]));

  for (const [owner, base] of basePorts) {
    const port = base + offset;
    if (port > 65535) {
      throw new Error(`${owner} をずらしたポート ${String(port)} が 65535 を超えます`);
    }
    const clash = baseOwners.get(port);
    if (offset !== 0 && clash !== undefined) {
      throw new Error(
        `${owner} をずらしたポート ${String(port)} が、ずらし 0 の ${clash} と重なります。firebase.json のポートかずらし幅を変えてください`,
      );
    }
    const [name, key] = owner.split(".");
    const settings = name === undefined ? undefined : emulatorSettings[name];
    if (settings !== undefined && key !== undefined) {
      settings[key] = port;
    }
  }
  return shifted;
}

/**
 * Emulator で動かさない拡張（`extensions`）を外した設定を作る。元のオブジェクトは変えない。
 * firebase.json の Trigger Email 拡張（firestore-send-email）は、Emulator では拡張のコードを取りに行き（ネットワーク）、
 * SMTP の接続先・送り主（人間が入れる値で、リポジトリには無い）を要るので起動できない。
 * テストは `reportCandidate` が `mail` に書いたドキュメントを読んで確かめる（拡張が送るところは本番でしか確かめられない）。
 * @param {Record<string, unknown>} config firebase.json の内容
 * @returns {Record<string, unknown>}
 */
function withoutExtensions(config) {
  const copy = structuredClone(config);
  delete copy.extensions;
  return copy;
}

module.exports = { GENERATED_CONFIG_NAME, parseOffset, shiftEmulatorPorts, withoutExtensions };

// スクリプトとして実行されたときだけ書き出す（テストから関数だけ読み込めるように）
if (require.main === module) {
  const backendDir = join(__dirname, "..");
  const config = /** @type {Record<string, unknown>} */ (
    JSON.parse(readFileSync(join(backendDir, "firebase.json"), "utf8"))
  );
  const offset = parseOffset(process.env.DG_EMULATOR_PORT_OFFSET);
  const outPath = join(backendDir, GENERATED_CONFIG_NAME);
  writeFileSync(outPath, `${JSON.stringify(shiftEmulatorPorts(withoutExtensions(config), offset), null, 2)}\n`);
  process.stdout.write(`${outPath}\n`);
}
