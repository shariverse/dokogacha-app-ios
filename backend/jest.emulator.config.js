/**
 * Emulator に接続するテスト（ルール・Functions）の Jest の設定。
 * scripts/test-emulator.sh が emulators:exec の中から流す。単体で流すと接続先の環境変数が無いので失敗する。
 * @type {import("jest").Config}
 */
module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  roots: ["<rootDir>/test/emulator"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "<rootDir>/tsconfig.json" }],
  },
  // Emulator への接続は Mac が混んでいると遅くなるので、既定の 5 秒より長く待つ
  testTimeout: 30000,
};
