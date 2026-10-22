import { isEmulatorEnvironment, toFcmMessage } from "./sender";

describe("FCM に渡す形", () => {
  test("本文・ペイロード・音・スレッドを入れる", () => {
    expect(
      toFcmMessage({ token: "t", body: "本文", data: { roomId: "r1", target: "room", type: "unlocked" }, threadId: "r1" }),
    ).toEqual({
      token: "t",
      notification: { body: "本文" },
      data: { roomId: "r1", target: "room", type: "unlocked" },
      apns: { payload: { aps: { sound: "default", threadId: "r1" } } },
    });
  });
});

describe("Emulator かどうか（Emulator では FCM に送らない）", () => {
  test("Functions の Emulator・Emulator に繋いだテストでは Emulator", () => {
    expect(isEmulatorEnvironment({ FUNCTIONS_EMULATOR: "true" })).toBe(true);
    expect(isEmulatorEnvironment({ FIRESTORE_EMULATOR_HOST: "127.0.0.1:8180" })).toBe(true);
  });

  test("本番（どちらの環境変数も無い）では FCM", () => {
    expect(isEmulatorEnvironment({})).toBe(false);
    expect(isEmulatorEnvironment({ FUNCTIONS_EMULATOR: "false", FIRESTORE_EMULATOR_HOST: "" })).toBe(false);
  });
});
