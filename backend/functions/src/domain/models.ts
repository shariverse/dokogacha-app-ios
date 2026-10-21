/**
 * Firestore のドキュメントの型（05 の §3 のデータモデル）。
 * Swift 側の `Dokogacha/Domain/Models/` と同じフィールド名・値。片方を変えたら両方を変える。
 *
 * - ドキュメントの ID はフィールドに入れない（パスにある）。Swift 側は `Identified` で ID と組にする
 * - 日時は Firestore の `Timestamp`（Swift 側は `Date`。変換はアプリのデータ層で行う）
 * - 05 の表で任意（`?`）のフィールドは、無い・`null` のどちらも「未設定」として扱う
 *   （更新でフィールドを消す代わりに `null` を書けるようにするため。Swift の `Optional` はどちらも nil で読む）
 */
import type { Timestamp } from "firebase-admin/firestore";

import type { PlaceCategory } from "./category";

/** ルームの状態（02 の §2.1）。`rooms.status` の値 */
export const ROOM_STATUSES = ["open", "unlocked", "drawn", "closed"] as const;
/** ルームの状態 */
export type RoomStatus = (typeof ROOM_STATUSES)[number];

/** 解禁の条件（F-31）。`rooms.settings.unlockRule` の値 */
export const UNLOCK_RULES = ["all", "majority", "deadline"] as const;
/** 解禁の条件 */
export type UnlockRule = (typeof UNLOCK_RULES)[number];

/** いいねの効き方（F-21）。`rooms.settings.likeMode` の値 */
export const LIKE_MODES = ["boost", "equal"] as const;
/** いいねの効き方 */
export type LikeMode = (typeof LIKE_MODES)[number];

/** メンバーの役割。`members.role` の値 */
export const MEMBER_ROLES = ["owner", "member"] as const;
/** メンバーの役割 */
export type MemberRole = (typeof MEMBER_ROLES)[number];

/** 引き直しの投票の状態（F-43）。`rooms.reroll.status` の値 */
export const REROLL_STATUSES = ["none", "voting", "passed", "rejected"] as const;
/** 引き直しの投票の状態 */
export type RerollStatus = (typeof REROLL_STATUSES)[number];

/** 投稿の報告の理由（F-14 の「不適切な内容／スパム／その他」）。`reports.reason` の値 */
export const REPORT_REASONS = ["inappropriate", "spam", "other"] as const;
/** 投稿の報告の理由 */
export type ReportReason = (typeof REPORT_REASONS)[number];

/**
 * 値が一覧のどれかか。Callable の入力の検証に使う。
 * @param values 値の一覧（`ROOM_STATUSES` など）
 * @param value 検証する値
 * @returns 一覧のどれかなら true
 */
export function isOneOf<T extends string>(values: readonly T[], value: unknown): value is T {
  return typeof value === "string" && (values as readonly string[]).includes(value);
}

/** ユーザーのプロフィール（`users/{uid}`） */
export interface UserDoc {
  /** 表示名（1〜10 文字） */
  displayName: string;
  /** アバターの色（`AVATAR_COLORS` の `#RRGGBB`） */
  avatarColor: string;
  /** 広告非表示を購入済みか（`verifyPurchase` だけが書き込む） */
  adFree: boolean;
  /** 通知のトークン（FCM） */
  fcmTokens: string[];
  /** 作成日時 */
  createdAt: Timestamp;
}

/** 候補の場所（`candidates.place`・`pastIdeas.place`） */
export interface Place {
  /** 場所名 */
  name: string;
  /** エリアの表示（「東京・豊島区」の形） */
  area: string;
  /** 緯度 */
  latitude: number;
  /** 経度 */
  longitude: number;
  /** `MKMapItem.identifier`（iOS 18 以降で取れたときだけ） */
  mapItemId?: string | null;
}

/** 過去のアイデア（`users/{uid}/pastIdeas/{ideaId}`。ルームの終了時に Functions が作る） */
export interface PastIdeaDoc {
  /** 元のルームの ID */
  sourceRoomId: string;
  /** 元のルームの名前 */
  sourceRoomName: string;
  /** 元のルームが終了した日時（並び替え用） */
  sourceClosedAt: Timestamp;
  /** 元のルームで当選した場所の名前（「◯◯ ゆき」） */
  sourceWinnerName: string;
  /** 場所 */
  place: Place;
  /** カテゴリ */
  category: PlaceCategory;
  /** 前回のいいね数 */
  prevLikeCount: number;
}

/** ルームの設定（`rooms.settings`） */
export interface RoomSettings {
  /** 1 人あたりの投稿数（1〜10） */
  postLimit: number;
  /** 解禁の条件 */
  unlockRule: UnlockRule;
  /** 締切日時（`unlockRule` が `deadline` のときだけ） */
  deadlineAt?: Timestamp | null;
  /** いいねの効き方 */
  likeMode: LikeMode;
}

/** ルームの広告をなくしている購入者（`rooms.adFreeSponsor`） */
export interface AdFreeSponsor {
  /** 購入者の uid */
  uid: string;
  /** 購入者の表示名 */
  displayName: string;
}

/** 引き直しの状態（`rooms.reroll`。ルームにつき 1 回までなので、別のコレクションにせずルームの中に持つ） */
export interface RerollState {
  /** 引き直しの権利を使ったか */
  used: boolean;
  /** 提案した人の uid */
  proposedBy?: string | null;
  /** 提案した日時 */
  proposedAt?: Timestamp | null;
  /** 賛成した人の uid */
  votesFor: string[];
  /** 反対した人の uid */
  votesAgainst: string[];
  /** 投票の状態 */
  status: RerollStatus;
}

/** まだ誰も提案していない引き直しの状態（ルームの作成時の値。Swift 側の `RerollState.initial`） */
export function initialRerollState(): RerollState {
  return { used: false, votesFor: [], votesAgainst: [], status: "none" };
}

/** ルーム（`rooms/{roomId}`） */
export interface RoomDoc {
  /** ルーム名（1〜20 文字） */
  name: string;
  /** 作成者の uid */
  ownerId: string;
  /** 招待コード（6 文字。ハイフンなし） */
  inviteCode: string;
  /** 状態 */
  status: RoomStatus;
  /** 設定 */
  settings: RoomSettings;
  /** 作成者が強制解禁したか */
  forcedUnlock: boolean;
  /** メンバーの uid（クエリ用。最大 20） */
  memberIds: string[];
  /** メンバー数 */
  memberCount: number;
  /** 準備OKの人数 */
  readyCount: number;
  /** 候補の数 */
  candidateCount: number;
  /** 広告非表示の購入者（メンバーにいれば最初に参加した人） */
  adFreeSponsor?: AdFreeSponsor | null;
  /** 最新の抽選の ID */
  currentDrawId?: string | null;
  /** 当選した候補の ID */
  winnerCandidateId?: string | null;
  /** 引き直しで外れた候補の ID */
  excludedCandidateIds: string[];
  /** 引き直しの状態 */
  reroll: RerollState;
  /** 作成日時 */
  createdAt: Timestamp;
  /** 抽選の日時 */
  drawnAt?: Timestamp | null;
  /** 終了の日時 */
  closedAt?: Timestamp | null;
}

/** ルームのメンバー（`rooms/{roomId}/members/{uid}`。ドキュメントの ID がメンバーの uid） */
export interface MemberDoc {
  /** 表示名（参加時点のコピー。プロフィールを変えると Functions が更新する） */
  displayName: string;
  /** アバターの色（参加時点のコピー） */
  avatarColor: string;
  /** 役割 */
  role: MemberRole;
  /** 準備OK */
  ready: boolean;
  /** 参加した日時 */
  joinedAt: Timestamp;
  /** 最後にルームを見た日時（NEW の判定に使う。参加したときは `joinedAt` と同じ値で作る） */
  lastSeenAt: Timestamp;
}

/** 候補（`rooms/{roomId}/candidates/{candidateId}`） */
export interface CandidateDoc {
  /** 場所 */
  place: Place;
  /** カテゴリ */
  category: PlaceCategory;
  /** ひとこと（0〜40 文字） */
  note: string;
  /** 参考 URL */
  url?: string | null;
  /** 投稿した人の uid */
  postedBy: string;
  /** 投稿した人の表示名 */
  postedByName: string;
  /** 投稿順の通し番号（カプセルの色に使う） */
  colorIndex: number;
  /** いいねしたメンバーの uid */
  likedBy: string[];
  /** 過去のアイデアから持ち込んだときの元 */
  fromPastIdeaId?: string | null;
  /** 投稿日時 */
  createdAt: Timestamp;
}

/** 抽選の記録（`rooms/{roomId}/draws/{drawId}`。`drawGacha` だけが作る） */
export interface DrawDoc {
  /** 当選した候補の ID */
  candidateId: string;
  /** 当選時の確率（0〜1） */
  probability: number;
  /** 抽選時の重みのスナップショット（候補の ID → 重み） */
  weights: Record<string, number>;
  /** 回した人の uid */
  drawnBy: string;
  /** 回した人の表示名 */
  drawnByName: string;
  /** 引き直しの抽選か */
  isReroll: boolean;
  /** 抽選の日時 */
  createdAt: Timestamp;
}

/** 招待コードの索引（`inviteCodes/{code}`。ドキュメントの ID が招待コード） */
export interface InviteCodeDoc {
  /** コードが指すルームの ID */
  roomId: string;
  /** 発行した日時 */
  createdAt: Timestamp;
}

/** 投稿の報告（`reports/{id}`。`reportCandidate` だけが作る） */
export interface ReportDoc {
  /** 報告された候補のルームの ID */
  roomId: string;
  /** 報告された候補の ID */
  candidateId: string;
  /** 報告した人の uid */
  reporterId: string;
  /** 理由 */
  reason: ReportReason;
  /** 報告した日時 */
  createdAt: Timestamp;
}
