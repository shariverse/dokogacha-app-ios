import { readFileSync } from "node:fs";
import { join } from "node:path";

import { parseOffset, shiftEmulatorPorts } from "./emulator-config.cjs";

/** リポジトリの firebase.json */
const firebaseJson = JSON.parse(
  readFileSync(join(__dirname, "..", "firebase.json"), "utf8"),
) as Record<string, unknown>;

/** 設定から Emulator のポートを取り出す */
function portOf(config: Record<string, unknown>, emulator: string, key = "port"): unknown {
  const emulators = config.emulators as Record<string, Record<string, unknown>>;
  return emulators[emulator]?.[key];
}

describe("parseOffset", () => {
  it("未指定と空は 0", () => {
    expect(parseOffset(undefined)).toBe(0);
    expect(parseOffset("")).toBe(0);
  });

  it("整数を読む", () => {
    expect(parseOffset("100")).toBe(100);
  });

  it.each(["-1", "1.5", "abc", "100 "])("%j は失敗する", (raw) => {
    expect(() => parseOffset(raw)).toThrow("DG_EMULATOR_PORT_OFFSET");
  });
});

describe("shiftEmulatorPorts", () => {
  it("すべてのポートにずらし幅を足し、元の設定は変えない", () => {
    const shifted = shiftEmulatorPorts(firebaseJson, 100);
    expect(portOf(shifted, "firestore")).toBe(8180);
    expect(portOf(shifted, "firestore", "websocketPort")).toBe(9250);
    expect(portOf(shifted, "hub")).toBe(4500);
    expect(portOf(shifted, "logging")).toBe(4700);
    expect(portOf(firebaseJson, "firestore")).toBe(8080);
  });

  it("ポートを持たない設定（UI の無効化など）はそのまま残す", () => {
    const shifted = shiftEmulatorPorts(firebaseJson, 100);
    expect((shifted.emulators as Record<string, unknown>).ui).toEqual({ enabled: false });
    expect((shifted.emulators as Record<string, unknown>).singleProjectMode).toBe(true);
  });

  it("スロット b のずらし（100）で、スロット a（0）のポートと重ならない", () => {
    expect(() => shiftEmulatorPorts(firebaseJson, 100)).not.toThrow();
  });

  it("ずらした後のポートが、ずらし 0 のポートと重なると失敗する", () => {
    const config = { emulators: { hub: { port: 4400 }, logging: { port: 4500 } } };
    expect(() => shiftEmulatorPorts(config, 100)).toThrow("hub.port");
  });

  it("65535 を超えると失敗する", () => {
    expect(() => shiftEmulatorPorts(firebaseJson, 60000)).toThrow("65535");
  });
});
