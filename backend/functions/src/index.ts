/**
 * Cloud Functions（2nd gen）の入口。
 * Callable やトリガーの関数は、機能を作るタスクでここから export する（05_architecture.md の §5）。
 */
import { setGlobalOptions } from "firebase-functions/v2";

import { FUNCTIONS_REGION } from "./config";

// すべての関数のリージョンを東京にそろえる。関数ごとに指定し忘れて us-central1 に配置されるのを防ぐ
setGlobalOptions({ region: FUNCTIONS_REGION });
