/**
 * Callable の共通の入口。認証の確認と、想定していない例外の変換を 1 か所で行う。
 */
import { logger } from "firebase-functions/v2";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { appError } from "./errors";

/**
 * 呼んだ人の uid を返す。サインインしていなければ `unauthenticated`。
 * @param request Callable のリクエスト
 * @returns uid
 * @throws `unauthenticated`
 */
export function requireAuth(request: Pick<CallableRequest, "auth">): string {
  const uid = request.auth?.uid;
  if (uid === undefined || uid === "") {
    throw appError("unauthenticated");
  }
  return uid;
}

/**
 * Callable の処理を実行する。認証を確かめてから `handler` を呼び、`HttpsError` 以外の例外は
 * ログに残して `internal`（「通信できませんでした」）にする（内部の情報をアプリに返さない）。
 * @param name ログに出す関数の名前
 * @param request Callable のリクエスト
 * @param handler 処理（呼んだ人の uid と `request.data` を受け取る）
 * @returns 処理の結果
 */
export async function runCallable<Result>(
  name: string,
  request: Pick<CallableRequest, "auth" | "data">,
  handler: (uid: string, data: unknown) => Promise<Result>,
): Promise<Result> {
  const uid = requireAuth(request);
  try {
    return await handler(uid, request.data);
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error(`${name} で想定していないエラー`, { uid, error });
    throw appError("internal");
  }
}
