/**
 * 02 の上限と、06 の §4 の仮決めの値。
 * Swift 側は `Dokogacha/Domain/DomainConstants.swift` に同じ値を持つ。値を変えるときは両方を変える。
 *
 * 06 の §4 は「値は定数や Remote Config にまとめる」とあるが、Remote Config は使わず（アプリに SDK を入れていない）、
 * Swift と TypeScript の定数それぞれ 1 か所にまとめる。時間は Firestore の `Timestamp.toMillis()` と比べやすいようにミリ秒で持つ。
 */

/** 1 分のミリ秒 */
const MINUTE_MS = 60 * 1000;
/** 1 時間のミリ秒 */
const HOUR_MS = 60 * MINUTE_MS;
/** 1 日のミリ秒 */
const DAY_MS = 24 * HOUR_MS;

// MARK: 上限・入力の範囲（02）

/** 1 ルームのメンバーの最大数（02 の §0・§2.4・§9） */
export const MAX_MEMBERS = 20;
/** 表示名の文字数（02 の §1「1〜10文字、必須」） */
export const DISPLAY_NAME_LENGTH = { min: 1, max: 10 } as const;
/** ルーム名の文字数（02 の §2.2「1〜20文字。必須」） */
export const ROOM_NAME_LENGTH = { min: 1, max: 20 } as const;
/** 1 人あたりの投稿数の範囲（02 の §2.2「1〜10件」） */
export const POST_LIMIT_RANGE = { min: 1, max: 10 } as const;
/** 1 人あたりの投稿数の初期値（02 の §2.2） */
export const DEFAULT_POST_LIMIT = 3;
/** 1 ルームの候補の最大数（02 の §9「最大200件（20人×10件）」） */
export const MAX_CANDIDATES = MAX_MEMBERS * POST_LIMIT_RANGE.max;
/** ひとことの最大文字数（02 の §3.1「最大40文字」） */
export const NOTE_MAX_LENGTH = 40;
/** 同じ場所とみなす距離（02 の §3.1「場所名が同じで座標が100m以内」。メートル） */
export const DUPLICATE_DISTANCE_METERS = 100;
/**
 * 場所名の文字数（02 に無い。MapKit の検索結果の名前が収まる長さとして決めた）。
 * 場所名は MapKit から取るので、空にはならない
 */
export const PLACE_NAME_LENGTH = { min: 1, max: 100 } as const;
/** エリアの表示の文字数（02 に無い。「東京・豊島区」の形。MapKit から取れないときは空） */
export const PLACE_AREA_LENGTH = { min: 0, max: 50 } as const;
/** ひとことの文字数（02 の §3.1「最大40文字」。任意なので 0 文字も可） */
export const NOTE_LENGTH = { min: 0, max: NOTE_MAX_LENGTH } as const;
/** 参考 URL の最大の長さ（UTF-16 のコード単位。02 に無い。ブラウザが扱える長さの目安） */
export const CANDIDATE_URL_MAX_LENGTH = 2048;
/** MapKit の識別子（`MKMapItem.identifier`）の最大の長さ（UTF-16 のコード単位。02 に無い） */
export const MAP_ITEM_ID_MAX_LENGTH = 256;
/** 締切日時に選べる最も早い時刻の、今からのミリ秒（02 の §2.2「現在から1時間後」） */
export const DEADLINE_EARLIEST_FROM_NOW_MS = HOUR_MS;
/** 締切日時に選べる最も遅い時刻の、今からのミリ秒（02 の §2.2「30日後」） */
export const DEADLINE_LATEST_FROM_NOW_MS = 30 * DAY_MS;
/** 締切日時の初期値の日数（02 の §2.2「3日後の21:00」の 3 日） */
export const DEFAULT_DEADLINE_DAYS_LATER = 3;
/** 締切日時の初期値の時（02 の §2.2「3日後の21:00」の 21 時） */
export const DEFAULT_DEADLINE_HOUR = 21;
/** 1 ルームで引き直せる回数（02 の §6.4「ルームにつき1回まで」） */
export const REROLLS_PER_ROOM = 1;

// MARK: 出やすさ（02 の §4.3）

// 02 の §4.3 は「比 = 表示% ÷ 平均%」を 1.2・0.85 と比べる。比を浮動小数点で作ると `100 / 候補数` の割り算の誤差で
// 「1.2 ちょうど」が下に落ちうるので、比を百分率の整数（比 × 100 = 表示% × 候補数）で持って整数どうしで比べる。

/** 出やすさのレベルが「出やすい」になる比の下限（百分率。比 ≥ 1.2。F-22） */
export const LEVEL_HIGH_RATIO_PERCENT = 120;
/** 出やすさのレベルが「ふつう」になる比の下限（百分率。0.85 ≤ 比。これより下は「レア」。F-22） */
export const LEVEL_MID_RATIO_PERCENT = 85;

// MARK: 仮決め（06 の §4）

/** 広告非表示の買い切りの StoreKit 2 のアイテムの ID（02 の §7.2・05 の §1） */
export const REMOVE_ADS_PRODUCT_ID = "remove_ads";
/** 広告非表示の価格（円。06 の §4 の仮決め ¥480） */
export const REMOVE_ADS_PRICE_YEN = 480;

/** Web のドメイン（06 の §4 の仮決め `dokogacha.app`） */
export const WEB_DOMAIN = "dokogacha.app";
/** 招待リンクのパスの前置き（`https://dokogacha.app/r/{招待コード}`。02 の §2.4） */
export const INVITE_LINK_PATH_PREFIX = "/r/";
/** 招待リンクの OGP のタイトル（06 の §4 の仮決め「固定画像・固定タイトル」。05 の §7） */
export const OGP_TITLE = "ドコガチャに招待されました";

/** 引き直しの投票の期限（06 の §4 の仮決め 24 時間。ミリ秒） */
export const REROLL_VOTING_DURATION_MS = 24 * HOUR_MS;
/** 引き直しの投票の期限を判定する間隔（05 の §5「expireRerolls：スケジュール（1時間ごと）」。期限の後、最大でこの分だけ遅れて否決になる） */
export const REROLL_EXPIRY_CHECK_INTERVAL_MINUTES = 60;
/** 抽選から自動で終了するまで（06 の §4 の仮決め 7 日。ミリ秒） */
export const AUTO_CLOSE_AFTER_DRAW_MS = 7 * DAY_MS;
/** 締切日時の解禁を判定する間隔（06 の §4 の仮決め 5 分） */
export const DEADLINE_CHECK_INTERVAL_MINUTES = 5;
/** 新しい候補のまとめ通知の時刻（06 の §4 の仮決め「1日1回 20:00 JST」） */
export const NEW_CANDIDATES_DIGEST_TIME = { hour: 20, minute: 0 } as const;
/** 新しい候補のまとめ通知を同じルームに送る 1 日あたりの最大回数 */
export const NEW_CANDIDATES_DIGEST_PER_DAY = 1;
/** スケジュールの時刻のタイムゾーン（JST） */
export const SCHEDULE_TIME_ZONE = "Asia/Tokyo";

/** 「前回惜しかった」バッジを付ける前回のいいね数の下限（06 の §4 の仮決め「前回のいいね3以上」） */
export const CLOSE_CALL_MIN_LIKES = 3;
/** 「みんな推し」の割合（06 の §4 の仮決め「投稿者以外の6割以上」。いいね数 ≥ ceil(n' × 0.6)） */
export const POPULAR_RATIO = 0.6;
/** 「みんな推し」に要るいいね数の下限（02 の §4.4「かついいね数 ≥ 2」） */
export const POPULAR_MIN_LIKES = 2;
/** 「全員いいね」に要る、投稿者以外のメンバー数 n' の下限（02 の §4.4「かつ n' ≥ 2」） */
export const ALL_LIKED_MIN_OTHER_MEMBERS = 2;

// アバターの色（06 の §4 の仮決め「ユーザー作成時にランダム。ルーム内の重複は許容」）は avatarPalette.ts に置く。
// 場所検索の範囲（06 の §4 の仮決め「日本全国」）は、検索するアプリ側だけで使うので Swift 側にだけ置く。
