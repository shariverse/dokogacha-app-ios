/**
 * Emulator がずらしたポートで起動していることを確かめる。
 * 2 つの作業スロットで同時に流したときにポートがぶつからないこと（DG_EMULATOR_PORT_OFFSET）の確認を兼ねる。
 */
import { expectedPort, requireEnv } from "./env";

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

describe("Emulator", () => {
  let running: RunningEmulators;

  beforeAll(async () => {
    const hub = requireEnv("FIREBASE_EMULATOR_HUB");
    const response = await fetch(`http://${hub}/emulators`);
    expect(response.ok).toBe(true);
    running = (await response.json()) as RunningEmulators;
  });

  it.each(["hub", "logging", "auth", "firestore", "functions", "hosting", "eventarc", "tasks"])(
    "%s が firebase.json のポート＋ずらしで起動している",
    (name) => {
      expect(running[name]?.port).toBe(expectedPort(name));
    },
  );
});
