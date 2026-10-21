/**
 * Cloud Functions（2nd gen）の入口。
 * Callable やトリガーの関数は、機能を作るタスクでここから export する（05_architecture.md の §5）。
 * 処理の中身は `rooms/`・`users/` にあり、ここでは Callable に包むだけにする（Emulator のテストは中身を直接呼べる）。
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall } from "firebase-functions/v2/https";

import { runCallable } from "./callable";
import { FUNCTIONS_REGION } from "./config";
import { defaultDeps } from "./deps";
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
