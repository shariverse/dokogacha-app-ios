/**
 * 単体テスト（Emulator を使わない）の Jest の設定。Functions のコードと backend のスクリプトのテストを流す。
 * Emulator のテストは jest.emulator.config.js で別に流す。
 * @type {import("jest").Config}
 */
module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  roots: ["<rootDir>/functions/src", "<rootDir>/scripts"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "<rootDir>/tsconfig.json" }],
  },
};
