// Jest の設定（jest.config.js・jest.emulator.config.js）で共有する部品。
"use strict";

/**
 * firebase-functions の `v2/https`（`HttpsError`・`onCall`）は firebase-admin の auth を読み込み、
 * それが ESM だけで配られている `jose` を require する。Jest は Node 22 では ESM を require できず
 * 「Must use import to load ES Module」で落ちるので、`jose` だけを ts-jest で CommonJS に変換する。
 */
const JOSE_TRANSFORM = {
  "/node_modules/jose/.+\\.js$": [
    "ts-jest",
    {
      tsconfig: { allowJs: true, module: "commonjs", target: "ES2023", isolatedModules: true },
      diagnostics: false,
    },
  ],
};

/** node_modules のうち `jose` だけを変換の対象にする（既定はすべての node_modules を変換しない） */
const JOSE_TRANSFORM_IGNORE_PATTERNS = ["/node_modules/(?!jose/)"];

module.exports = { JOSE_TRANSFORM, JOSE_TRANSFORM_IGNORE_PATTERNS };
