/**
 * Callable の処理が使う外部のもの（Firestore・乱数・時刻）。
 * 処理は引数でこれを受け取り、Emulator のテストでは乱数を差し替えて重複などを再現する。
 */
import { Timestamp, type Firestore } from "firebase-admin/firestore";

import { cryptoRandomInt, type RandomInt } from "./domain/random";

/** Callable の処理が使う外部のもの */
export interface ServiceDeps {
  /** Firestore（Admin SDK。ルールを通らない） */
  db: Firestore;
  /** 乱数（招待コード・アバターの色） */
  random: RandomInt;
  /** サーバーの今の時刻（UNIX 時刻のミリ秒。入力の検証に使う。書き込む日時は `FieldValue.serverTimestamp()`） */
  nowMs: () => number;
}

/**
 * 本番（と Emulator の Functions）で使う外部のもの。
 * @param db Firestore
 * @returns 乱数は `crypto.randomInt`、時刻は `Timestamp.now()`
 */
export function defaultDeps(db: Firestore): ServiceDeps {
  return { db, random: cryptoRandomInt, nowMs: () => Timestamp.now().toMillis() };
}
