/**
 * 単体テスト（Emulator を使わない）の Jest の設定。Functions のコード・backend のスクリプト・Hosting のテストを流す。
 * Emulator のテストは jest.emulator.config.js で別に流す。
 * @type {import("jest").Config}
 */
const { JOSE_TRANSFORM, JOSE_TRANSFORM_IGNORE_PATTERNS } = require("./jest.shared.cjs");

module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  roots: ["<rootDir>/functions/src", "<rootDir>/scripts", "<rootDir>/hosting/test"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "<rootDir>/tsconfig.json" }],
    ...JOSE_TRANSFORM,
  },
  transformIgnorePatterns: JOSE_TRANSFORM_IGNORE_PATTERNS,
};
