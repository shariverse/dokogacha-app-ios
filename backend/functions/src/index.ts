/**
 * Cloud Functions（2nd gen）の入口。
 * Callable やトリガーの関数は、機能を作るタスクでここから export する（05_architecture.md の §5）。
 * 処理の中身は `rooms/`・`users/`・`candidates/` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼べる）。
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "./callable";
import * as candidates from "./candidates/service";
import { FUNCTIONS_REGION } from "./config";
import { defaultDeps } from "./deps";
import * as rooms from "./rooms/service";
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

/** 候補を追加する（02 の F-10。同じ場所があれば作らずに `{ duplicateOf }` を返す） */
export const addCandidate = onCall((request) =>
  runCallable("addCandidate", request, (uid, data) => candidates.addCandidate(deps(), uid, data)),
);

/** 候補を削除する（02 の F-11。投稿した人か作成者だけ） */
export const deleteCandidate = onCall((request) =>
  runCallable("deleteCandidate", request, (uid, data) => candidates.deleteCandidate(deps(), uid, data)),
);
