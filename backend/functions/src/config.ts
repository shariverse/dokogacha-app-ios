/**
 * Cloud Functions 全体で共有する設定値。
 * 値をこのファイルに集めておくと、Swift 側の定数と食い違ったときに探す場所が 1 か所で済む。
 */

/**
 * Functions を配置するリージョン（東京）。
 * Firestore と同じリージョンにそろえて、トリガーと読み書きの往復を短くする（Discussion #5 の Q3）。
 */
export const FUNCTIONS_REGION = "asia-northeast1";
