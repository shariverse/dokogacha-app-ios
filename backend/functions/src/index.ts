/**
 * Cloud Functions（2nd gen）の入口。
 * Callable やトリガーの関数は、機能を作るタスクでここから export する（05_architecture.md の §5）。
 * 処理の中身は `rooms/`・`users/`・`candidates/`・`unlock/`・`settings/`・`draw/`・`reroll/` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼べる）。
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { runCallable } from "./callable";
import * as candidates from "./candidates/service";
import { FUNCTIONS_REGION } from "./config";
import { defaultDeps } from "./deps";
import { DEADLINE_CHECK_INTERVAL_MINUTES, REROLL_EXPIRY_CHECK_INTERVAL_MINUTES, SCHEDULE_TIME_ZONE } from "./domain/constants";
import type { MemberDoc, RoomDoc } from "./domain/models";
import { drawnEventOf } from "./draw/logic";
import { notifyRoomDrawn } from "./draw/notify";
import * as draw from "./draw/service";
import * as reroll from "./reroll/service";
import * as rooms from "./rooms/service";
import * as settings from "./settings/service";
import { memberWriteAffectsUnlock } from "./unlock/logic";
import * as unlock from "./unlock/service";
import type { ProfileCopy } from "./users/logic";
import { handleProfileUpdate } from "./users/profileSync";
import * as users from "./users/service";

// すべての関数のリージョンを東京にそろえる。関数ごとに指定し忘れて us-central1 に配置されるのを防ぐ
setGlobalOptions({ region: FUNCTIONS_REGION });

initializeApp();

/** Callable の処理が使う外部のもの（呼ばれたときに作る。読み込みの時点では Firestore に繋がない） */
const deps = () => defaultDeps(getFirestore());

/** 表示名を登録・変更する（02 の F-01。`users/{uid}` をまだ作っていなければ作る） */
export const saveProfile = onCall((request) =>
  runCallable("saveProfile", request, (uid, data) => users.saveProfile(deps(), uid, data)),
);

/**
 * プロフィールの表示名・アバターの色が変わったら、参加中のルームの複製（メンバー・自分の候補の投稿者名・広告の購入者）に反映する
 * （05 の §5。Firestore のトリガー）。通知のトークンだけの更新などでは何もしない。
 * 一部のルームで失敗したら、残りを処理してから投げてやり直させる（`retry: true`。反映は冪等）
 */
export const onUserProfileUpdate = onDocumentUpdated({ document: "users/{uid}", retry: true }, async (event) => {
  const before = event.data?.before.data() as Partial<ProfileCopy> | undefined;
  const after = event.data?.after.data() as Partial<ProfileCopy> | undefined;
  const uid = event.params.uid;
  const result = await handleProfileUpdate(getFirestore(), uid, before, after);
  if (result !== null) {
    logger.info("プロフィールをルームの複製に反映した", { uid, ...result });
  }
});

/** ルームを作る（02 の F-02） */
export const createRoom = onCall((request) =>
  runCallable("createRoom", request, (uid, data) => rooms.createRoom(deps(), uid, data)),
);

/** 招待コードでルームに参加する（02 の F-04） */
export const joinRoom = onCall((request) =>
  runCallable("joinRoom", request, (uid, data) => rooms.joinRoom(deps(), uid, data)),
);

/** 招待コードで参加する前に、参加するルームを確かめる（03 の S-06。何も書き込まない） */
export const previewRoom = onCall((request) =>
  runCallable("previewRoom", request, (uid, data) => rooms.previewRoom(deps(), uid, data)),
);

/** ルームから退出する（02 の F-05） */
export const leaveRoom = onCall((request) =>
  runCallable("leaveRoom", request, (uid, data) => rooms.leaveRoom(deps(), uid, data)),
);

/** 作成者がメンバーを削除する（02 の F-05） */
export const removeMember = onCall((request) =>
  runCallable("removeMember", request, (uid, data) => rooms.removeMember(deps(), uid, data)),
);

/** 作成者がルームの設定を変える（02 の F-03 の変更ルール。変えた後に解禁を判定し直す） */
export const updateRoomSettings = onCall((request) =>
  runCallable("updateRoomSettings", request, (uid, data) => settings.updateRoomSettings(deps(), uid, data)),
);

/** ルームの終了（02 の F-44）: closeRoom（作成者の決定）・autoCloseRooms（抽選から 7 日）・onRoomClosed（過去のアイデアの登録） */
export { autoCloseRooms, closeRoom, onRoomClosed } from "./close/functions";

/** 前回のメンバーへの招待（02 の F-04）: inviteLastMembers */
export { inviteLastMembers } from "./invite/functions";

/** 候補を追加する（02 の F-10。同じ場所があれば作らずに `{ duplicateOf }` を返す） */
export const addCandidate = onCall((request) =>
  runCallable("addCandidate", request, (uid, data) => candidates.addCandidate(deps(), uid, data)),
);

/** 候補を削除する（02 の F-11。投稿した人か作成者だけ） */
export const deleteCandidate = onCall((request) =>
  runCallable("deleteCandidate", request, (uid, data) => candidates.deleteCandidate(deps(), uid, data)),
);

/**
 * メンバーの参加・退出・削除・準備OKの変更で、`memberCount`・`readyCount` を数え直し、解禁の条件（F-31）を判定して
 * `status` を `open`⇄`unlocked` に変える（05 の §5。Firestore のトリガー）。`unlocked` にしたら通知の呼び出し口を呼ぶ。
 * `lastSeenAt`・表示名の複製だけの更新では何もしない。ルームだけに書くので、自分の書き込みでもう一度動かない。
 * 失敗したらやり直す（`retry: true`。数え直しは冪等）
 */
export const onMemberWrite = onDocumentWritten(
  { document: "rooms/{roomId}/members/{uid}", retry: true },
  async (event) => {
    const before = event.data?.before.data() as Partial<MemberDoc> | undefined;
    const after = event.data?.after.data() as Partial<MemberDoc> | undefined;
    if (!memberWriteAffectsUnlock(before, after)) {
      return;
    }
    const roomId = event.params.roomId;
    const result = await unlock.recountRoom(deps(), roomId);
    if (result.changed) {
      logger.info("メンバーを数え直して解禁を判定した", { roomId, ...result });
    }
  },
);

/** 作成者が強制解禁する（02 の F-32。open のときだけ） */
export const forceUnlock = onCall((request) =>
  runCallable("forceUnlock", request, (uid, data) => unlock.forceUnlock(deps(), uid, data)),
);

/**
 * 締切日時を過ぎた open のルームを unlocked にする（02 の §5.2・05 の §5。5 分ごと。06 の §4 の仮決め）。
 * 一部のルームで失敗しても残りを処理してから投げる（次の実行でもう一度拾う）
 */
export const checkDeadlines = onSchedule(
  { schedule: `every ${String(DEADLINE_CHECK_INTERVAL_MINUTES)} minutes`, timeZone: SCHEDULE_TIME_ZONE },
  async () => {
    const result = await unlock.unlockPassedDeadlines(deps());
    if (result.rooms > 0) {
      logger.info("締切日時を過ぎたルームを判定した", result);
    }
  },
);

/**
 * ガチャを回す（02 の F-40。サーバーの乱数 `crypto.randomInt` で抽選する）。
 * 先に誰かが回していれば、抽選せずにその結果（同じ `drawId`）を返す
 */
export const drawGacha = onCall((request) =>
  runCallable("drawGacha", request, (uid, data) => draw.drawGacha(deps(), uid, data)),
);

/**
 * ルームが `drawn` になったら（引き直しの後にもう一度回したときも）、回した人以外に結果を知らせる通知を送る
 * （05 の §5。Firestore のトリガー）。`drawn` のままの更新（数え直しなど）では何もしない。
 * 失敗したらやり直す（`retry: true`。通知は抽選の ID ごとに 1 回しか送らないので、やり直しても 2 回届かない）
 */
export const onRoomDrawn = onDocumentUpdated({ document: "rooms/{roomId}", retry: true }, async (event) => {
  const before = event.data?.before.data() as Partial<RoomDoc> | undefined;
  const after = event.data?.after.data() as Partial<RoomDoc> | undefined;
  const drawn = drawnEventOf(before, after);
  if (drawn === null) {
    return;
  }
  await notifyRoomDrawn(deps(), event.params.roomId, drawn.drawId);
});

/** 引き直しを提案する（02 の F-43。drawn のときだけ・ルームにつき 1 回・提案者は自動で賛成） */
export const proposeReroll = onCall((request) =>
  runCallable("proposeReroll", request, (uid, data) => reroll.proposeReroll(deps(), uid, data)),
);

/** 引き直しに投票する（02 の F-43。賛成が過半数になったら、直前の当選を除外してルームを unlocked に戻す） */
export const voteReroll = onCall((request) =>
  runCallable("voteReroll", request, (uid, data) => reroll.voteReroll(deps(), uid, data)),
);

/**
 * 提案から 24 時間を過ぎた引き直しの投票を否決にする（02 の §6.4・05 の §5。1 時間ごと。06 の §4 の仮決め）。
 * 一部のルームで失敗しても残りを処理してから投げる（次の実行でもう一度拾う）
 */
export const expireRerolls = onSchedule(
  { schedule: `every ${String(REROLL_EXPIRY_CHECK_INTERVAL_MINUTES)} minutes`, timeZone: SCHEDULE_TIME_ZONE },
  async () => {
    const result = await reroll.expireRerolls(deps());
    if (result.rooms > 0) {
      logger.info("期限を過ぎた引き直しの投票を判定した", result);
    }
  },
);
