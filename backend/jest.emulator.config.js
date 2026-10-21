/**
 * Emulator に接続するテスト（ルール・Functions）の Jest の設定。
 * scripts/test-emulator.sh が emulators:exec の中から流す。単体で流すと接続先の環境変数が無いので失敗する。
 * @type {import("jest").Config}
 */
const { JOSE_TRANSFORM, JOSE_TRANSFORM_IGNORE_PATTERNS } = require("./jest.shared.cjs");

module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  roots: ["<rootDir>/test/emulator"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "<rootDir>/tsconfig.json" }],
    ...JOSE_TRANSFORM,
  },
  transformIgnorePatterns: JOSE_TRANSFORM_IGNORE_PATTERNS,
  // Emulator への接続は Mac が混んでいると遅くなるので、既定の 5 秒より長く待つ
  testTimeout: 30000,
  // テストのファイルどうしで同じ Emulator のデータを消し合わないよう、1 つずつ流す
  maxWorkers: 1,
};
