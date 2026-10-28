import * as constants from "./constants";

// 02 の上限と 06 の §4 の仮決めの値。Swift 側の DokogachaTests/DomainConstantsTests.swift と同じ値を確かめる。

describe("02 の上限・入力の範囲", () => {
  it("資料どおり", () => {
    expect(constants.MAX_MEMBERS).toBe(20);
    expect(constants.DISPLAY_NAME_LENGTH).toEqual({ min: 1, max: 10 });
    expect(constants.ROOM_NAME_LENGTH).toEqual({ min: 1, max: 20 });
    expect(constants.POST_LIMIT_RANGE).toEqual({ min: 1, max: 10 });
    expect(constants.DEFAULT_POST_LIMIT).toBe(3);
    expect(constants.MAX_CANDIDATES).toBe(200);
    expect(constants.NOTE_MAX_LENGTH).toBe(40);
    expect(constants.DUPLICATE_DISTANCE_METERS).toBe(100);
    expect(constants.PLACE_NAME_LENGTH).toEqual({ min: 1, max: 100 });
    expect(constants.PLACE_AREA_LENGTH).toEqual({ min: 0, max: 50 });
    expect(constants.NOTE_LENGTH).toEqual({ min: 0, max: 40 });
    expect(constants.CANDIDATE_URL_MAX_LENGTH).toBe(2048);
    expect(constants.MAP_ITEM_ID_MAX_LENGTH).toBe(256);
    expect(constants.DEADLINE_EARLIEST_FROM_NOW_MS).toBe(3_600_000);
    expect(constants.DEADLINE_LATEST_FROM_NOW_MS).toBe(30 * 86_400_000);
    expect(constants.DEFAULT_DEADLINE_DAYS_LATER).toBe(3);
    expect(constants.DEFAULT_DEADLINE_HOUR).toBe(21);
    expect(constants.REROLLS_PER_ROOM).toBe(1);
  });
});

describe("02 の §4.3 の出やすさのレベルの境目", () => {
  it("比 1.2・0.85 を百分率で持つ", () => {
    expect(constants.LEVEL_HIGH_RATIO_PERCENT).toBe(120);
    expect(constants.LEVEL_MID_RATIO_PERCENT).toBe(85);
  });
});

describe("06 の §4 の仮決め", () => {
  it("資料どおり", () => {
    expect(constants.REMOVE_ADS_PRODUCT_ID).toBe("remove_ads");
    expect(constants.REMOVE_ADS_PRICE_YEN).toBe(480);
    expect(constants.WEB_DOMAIN).toBe("dokogacha.app");
    expect(constants.INVITE_LINK_PATH_PREFIX).toBe("/r/");
    expect(constants.OGP_TITLE).toBe("ドコガチャに招待されました");
    expect(constants.REROLL_VOTING_DURATION_MS).toBe(24 * 3_600_000);
    expect(constants.AUTO_CLOSE_AFTER_DRAW_MS).toBe(7 * 86_400_000);
    expect(constants.DEADLINE_CHECK_INTERVAL_MINUTES).toBe(5);
    expect(constants.NEW_CANDIDATES_DIGEST_TIME).toEqual({ hour: 20, minute: 0 });
    expect(constants.NEW_CANDIDATES_DIGEST_PER_DAY).toBe(1);
    expect(constants.SCHEDULE_TIME_ZONE).toBe("Asia/Tokyo");
    expect(constants.CLOSE_CALL_MIN_LIKES).toBe(3);
    expect(constants.POPULAR_RATIO).toBe(0.6);
    expect(constants.POPULAR_MIN_LIKES).toBe(2);
    expect(constants.ALL_LIKED_MIN_OTHER_MEMBERS).toBe(2);
  });

  it("スケジュールのタイムゾーンは JST（UTC+9）", () => {
    const hour = new Intl.DateTimeFormat("en-US", {
      timeZone: constants.SCHEDULE_TIME_ZONE,
      hour: "numeric",
      hourCycle: "h23",
    }).format(new Date(Date.UTC(2026, 9, 22, 11, 0)));
    expect(hour).toBe("20");
  });
});
