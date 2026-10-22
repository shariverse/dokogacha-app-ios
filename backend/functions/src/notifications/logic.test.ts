import {
  audienceOf,
  excludedRecipient,
  MAX_TOKEN_LENGTH,
  MAX_TOKENS_PER_USER,
  notificationLogKey,
  pushBody,
  pushData,
  pushTarget,
  selectRecipients,
  unregisteredTokensByUser,
  validTokensOf,
  type PushEvent,
} from "./logic";

const unlocked: PushEvent = { kind: "unlocked", roomId: "r1", roomName: "年末の旅行" };
const drawn: PushEvent = { kind: "drawn", roomId: "r1", roomName: "年末の旅行", drawId: "d1", drawnBy: "alice" };
const reroll: PushEvent = { kind: "rerollProposed", roomId: "r1", drawId: "d1", proposedBy: "bob", proposerName: "ぼぶ" };
const invited: PushEvent = {
  kind: "invited",
  roomId: "r1",
  roomName: "年末の旅行",
  inviteCode: "DK729Q",
  inviterId: "alice",
  inviterName: "ありす",
  sourceRoomId: "old",
  inviteeIds: ["dave", "erin"],
};
const newCandidates: PushEvent = {
  kind: "newCandidates",
  roomId: "r1",
  roomName: "年末の旅行",
  dateKey: "2026-10-22",
  count: 3,
  onlyPosterId: null,
};

describe("前回のメンバーへの招待と新しい候補のまとめ（02 の §8）", () => {
  test("文面", () => {
    expect(pushBody(invited)).toBe("ありすさんから「年末の旅行」に招待されました");
    expect(pushBody(newCandidates)).toBe("「年末の旅行」に新しい候補が 3件増えました");
  });

  test("招待は招待コードで参加確認（join）、まとめはルームを開く", () => {
    expect(pushData(invited)).toEqual({ type: "invited", roomId: "r1", target: "join", inviteCode: "DK729Q" });
    expect(pushData(newCandidates)).toEqual({ type: "newCandidates", roomId: "r1", target: "room" });
  });

  test("招待の宛先は招待した人たち（ルームのメンバーではない）。まとめはメンバー", () => {
    expect(audienceOf(invited, ["alice"])).toEqual(["dave", "erin"]);
    expect(audienceOf(newCandidates, ["alice", "bob"])).toEqual(["alice", "bob"]);
    expect(audienceOf(unlocked, ["alice", "bob"])).toEqual(["alice", "bob"]);
  });

  test("招待は招待した人を、まとめは自分の投稿しか増えていない人を外す", () => {
    expect(excludedRecipient(invited)).toBe("alice");
    expect(excludedRecipient(newCandidates)).toBeNull();
    expect(excludedRecipient({ ...newCandidates, onlyPosterId: "bob" })).toBe("bob");
  });

  test("印のキー: 招待は招いた人と前回のルームごと、まとめはルームの日ごと", () => {
    expect(notificationLogKey(invited)).toBe("invited-alice-old");
    expect(notificationLogKey({ ...invited, sourceRoomId: "older" })).toBe("invited-alice-older");
    expect(notificationLogKey(newCandidates)).toBe("newCandidates-2026-10-22");
  });
});

describe("通知の文面（02 の §8）", () => {
  test("解禁・抽選結果・引き直し提案の文面", () => {
    expect(pushBody(unlocked)).toBe("「年末の旅行」のガチャが解禁されました！");
    expect(pushBody(drawn)).toBe("「年末の旅行」の行き先が決まりました");
    expect(pushBody(reroll)).toBe("ぼぶさんが引き直しを提案しています");
  });
});

describe("通知のペイロードと行き先（05 の §7）", () => {
  test("解禁はルーム、抽選結果と引き直しの提案は結果を開く", () => {
    expect(pushTarget(unlocked)).toBe("room");
    expect(pushTarget(drawn)).toBe("result");
    expect(pushTarget(reroll)).toBe("result");
  });

  test("ペイロードに種類・roomId・遷移先と、結果なら抽選の ID を入れる", () => {
    expect(pushData(unlocked)).toEqual({ type: "unlocked", roomId: "r1", target: "room" });
    expect(pushData(drawn)).toEqual({ type: "drawn", roomId: "r1", target: "result", drawId: "d1" });
    expect(pushData(reroll)).toEqual({ type: "rerollProposed", roomId: "r1", target: "result", drawId: "d1" });
  });

  test("抽選の ID が無ければ drawId を入れない", () => {
    expect(pushData({ ...reroll, drawId: null })).toEqual({ type: "rerollProposed", roomId: "r1", target: "result" });
    expect(pushData({ ...reroll, drawId: "" })).toEqual({ type: "rerollProposed", roomId: "r1", target: "result" });
  });
});

describe("同じ通知を 2 回送らない印のキー", () => {
  test("解禁と提案はルームにつき 1 つ、抽選結果は抽選ごと", () => {
    expect(notificationLogKey(unlocked)).toBe("unlocked");
    expect(notificationLogKey(reroll)).toBe("rerollProposed");
    expect(notificationLogKey(drawn)).toBe("drawn-d1");
    expect(notificationLogKey({ ...drawn, drawId: "d2" })).toBe("drawn-d2");
  });
});

describe("宛先（02 の §8 の「宛先」）", () => {
  const members = ["alice", "bob", "carol"];
  const users = [
    { uid: "alice", fcmTokens: ["ta"] },
    { uid: "bob", fcmTokens: ["tb1", "tb2"] },
    { uid: "carol", fcmTokens: ["tc"] },
  ];

  test("外す人がいる出来事: 解禁は全員、抽選結果は回した人以外、提案は提案者以外", () => {
    expect(excludedRecipient(unlocked)).toBeNull();
    expect(excludedRecipient(drawn)).toBe("alice");
    expect(excludedRecipient(reroll)).toBe("bob");
  });

  test("解禁は全メンバーのすべてのトークンに送る", () => {
    expect(selectRecipients(members, null, users)).toEqual([
      { uid: "alice", token: "ta" },
      { uid: "bob", token: "tb1" },
      { uid: "bob", token: "tb2" },
      { uid: "carol", token: "tc" },
    ]);
  });

  test("自分（回した人・提案した人）を外す", () => {
    expect(selectRecipients(members, "alice", users).map((r) => r.uid)).toEqual(["bob", "bob", "carol"]);
  });

  test("トークンが無い人・ドキュメントが無い人は外す", () => {
    const sparse = [
      { uid: "alice", fcmTokens: [] },
      { uid: "bob", fcmTokens: undefined },
      { uid: "carol", fcmTokens: ["tc"] },
    ];
    expect(selectRecipients(members, null, sparse)).toEqual([{ uid: "carol", token: "tc" }]);
  });

  test("メンバーでない人（退出した人）には送らない", () => {
    expect(selectRecipients(["alice"], null, users)).toEqual([{ uid: "alice", token: "ta" }]);
  });

  test("同じトークンは 1 回だけ（先に見つけた人を持ち主にする）", () => {
    const shared = [
      { uid: "alice", fcmTokens: ["same"] },
      { uid: "bob", fcmTokens: ["same", "tb"] },
    ];
    expect(selectRecipients(["alice", "bob"], null, shared)).toEqual([
      { uid: "alice", token: "same" },
      { uid: "bob", token: "tb" },
    ]);
  });

  test("壊れたトークンは読まない（文字列でない・空・長すぎる。上限の数まで）", () => {
    expect(validTokensOf("token")).toEqual([]);
    expect(validTokensOf(null)).toEqual([]);
    expect(validTokensOf(["ok", "", 1, "t".repeat(MAX_TOKEN_LENGTH + 1), "t".repeat(MAX_TOKEN_LENGTH)])).toEqual([
      "ok",
      "t".repeat(MAX_TOKEN_LENGTH),
    ]);
    const many = Array.from({ length: MAX_TOKENS_PER_USER + 5 }, (_, i) => `t${String(i)}`);
    expect(validTokensOf(many)).toHaveLength(MAX_TOKENS_PER_USER);
  });
});

describe("無効なトークンを外す", () => {
  const recipients = [
    { uid: "alice", token: "ta" },
    { uid: "bob", token: "tb1" },
    { uid: "bob", token: "tb2" },
    { uid: "carol", token: "tc" },
  ];

  test("登録されていない・形が正しくないトークンだけを持ち主ごとにまとめる", () => {
    const result = unregisteredTokensByUser(recipients, [
      { success: true },
      { success: false, errorCode: "messaging/registration-token-not-registered" },
      { success: false, errorCode: "messaging/invalid-registration-token" },
      { success: false, errorCode: "messaging/internal-error" },
    ]);
    expect(Object.fromEntries(result)).toEqual({ bob: ["tb1", "tb2"] });
  });

  test("一時的な失敗（FCM の障害・通信）では外さない", () => {
    const result = unregisteredTokensByUser(recipients, [
      { success: false, errorCode: "messaging/server-unavailable" },
      { success: false, errorCode: "messaging/internal-error" },
      { success: false },
      { success: false, errorCode: "messaging/invalid-argument" },
    ]);
    expect(result.size).toBe(0);
  });
});
