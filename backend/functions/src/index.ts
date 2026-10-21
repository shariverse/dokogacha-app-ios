/**
 * Cloud Functions（2nd gen）の入口。
 * Callable やトリガーの関数は、機能を作るタスクでここから export する（05_architecture.md の §5）。
 * 処理の中身は `rooms/`・`users/`・`candidates/` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼べる）。
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "./callable";
import * as candidates from "./candidates/service";
import { FUNCTIONS_REGION } from "./config";
import { defaultDeps } from "./deps";
import * as rooms from "./rooms/service";
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

/** ルームを作る（02 の F-02） */
export const createRoom = onCall((request) =>
  runCallable("createRoom", request, (uid, data) => rooms.createRoom(deps(), uid, data)),
);

/** 招待コードでルームに参加する（02 の F-04） */
export const joinRoom = onCall((request) =>
  runCallable("joinRoom", request, (uid, data) => rooms.joinRoom(deps(), uid, data)),
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
