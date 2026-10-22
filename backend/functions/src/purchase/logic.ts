/**
 * 広告非表示の買い切り（02 の §7.2 F-51・05 の §5 の `verifyPurchase`）の判定。Firestore と App Store の検証を使わない純粋な関数。
 * - 検証したトランザクションで広告非表示にしてよいか（`decidePurchase`）
 * - どの環境（Production・Sandbox・Xcode）の署名として確かめるか（`verificationEnvironments`）
 * - 購入した人が参加しているルームの購入者（`adFreeSponsor`）を誰にするか（`sponsorAfterPurchase`）
 * Swift 側の擬似のサーバー（`InMemoryServer+Purchase.swift`）も同じ決まりで動く。
 */
import { REMOVE_ADS_PRODUCT_ID } from "../domain/constants";
import type { AdFreeSponsor } from "../domain/models";

/** 署名を確かめる App Store の環境（`@apple/app-store-server-library` の `Environment` の値と同じ文字列） */
export type PurchaseEnvironment = "Production" | "Sandbox" | "Xcode";

/** 検証した署名付きトランザクションのうち、判定に使う値（App Store Server Library の `JWSTransactionDecodedPayload` から写す） */
export interface VerifiedTransaction {
  /** アイテムの ID */
  productId: string | undefined;
  /** トランザクションの ID（ログ用） */
  transactionId: string | undefined;
  /** 最初の購入のトランザクションの ID（復元しても変わらない。ログ用） */
  originalTransactionId: string | undefined;
  /** 署名された環境 */
  environment: PurchaseEnvironment;
  /** 返金・ファミリー共有の取り消しで取り消された日時（UNIX 時刻のミリ秒。取り消されていなければ undefined） */
  revocationDate: number | undefined;
}

/** 検証したトランザクションの判定 */
export type PurchaseDecision = { kind: "grant" } | { kind: "reject"; why: "other-product" | "revoked" };

/**
 * 検証したトランザクションで広告非表示にしてよいか。
 * 広告非表示のアイテム（`remove_ads`）で、取り消されていないものだけを受け付ける。
 * 別のアプリのもの（Bundle ID）・別の環境のものは、検証（`verifier.ts`）で断っている。
 * @param transaction 検証したトランザクション
 * @returns 判定
 */
export function decidePurchase(transaction: Pick<VerifiedTransaction, "productId" | "revocationDate">): PurchaseDecision {
  if (transaction.productId !== REMOVE_ADS_PRODUCT_ID) {
    return { kind: "reject", why: "other-product" };
  }
  if (transaction.revocationDate !== undefined) {
    return { kind: "reject", why: "revoked" };
  }
  return { kind: "grant" };
}

/** 署名を確かめる環境を決めるのに使う設定 */
export interface VerificationSettings {
  /** Emulator で動いているか（Xcode の StoreKit のテストの署名も受け付ける） */
  emulator: boolean;
  /** App Store Connect のアプリの ID（Apple ID。数字）。まだ無い（アプリを登録していない）ときは undefined */
  appAppleId: number | undefined;
}

/**
 * 署名を確かめる環境（前から順に試す）。
 * - 本番（と dev）の Functions: Production → Sandbox。審査と TestFlight の購入は Sandbox で署名されるので、Sandbox も受け付ける
 *   （Apple の勧める順。Production で環境が違うと分かったら Sandbox で確かめ直す）。
 *   Production の検証にはアプリの ID が要るので、まだ無いときは Sandbox だけ
 * - Emulator: Xcode → Sandbox。Xcode の StoreKit のテスト（`.storekit`）の署名は App Store の証明書ではなく、
 *   App Store Server Library は Xcode の環境では署名を確かめない。本番で受け付けると誰でも作れるので、Emulator だけにする
 * @param settings 設定
 * @returns 試す環境の並び
 */
export function verificationEnvironments(settings: VerificationSettings): PurchaseEnvironment[] {
  if (settings.emulator) {
    return ["Xcode", "Sandbox"];
  }
  return settings.appAppleId === undefined ? ["Sandbox"] : ["Production", "Sandbox"];
}

/**
 * Functions のパラメータのアプリの ID（文字列）を数にする。空・数字でないときは undefined（まだアプリを登録していない）。
 * @param value パラメータの値
 * @returns アプリの ID
 */
export function parseAppAppleId(value: string): number | undefined {
  const trimmed = value.trim();
  if (!/^[1-9][0-9]{0,18}$/u.test(trimmed)) {
    return undefined;
  }
  const id = Number(trimmed);
  return Number.isSafeInteger(id) ? id : undefined;
}

/** 参加の順を比べるための、メンバーの参加日時と uid */
export interface JoinOrder {
  /** uid */
  uid: string;
  /** 参加日時（UNIX 時刻のミリ秒） */
  joinedAtMs: number;
}

/**
 * `a` が `b` より先に参加したか。同じ日時なら uid の小さい方を先にする
 * （退出したときに探し直す `sponsorAfterRemoval` は `orderBy("joinedAt")` で読み、同じ日時はドキュメントの ID の順に並ぶため）。
 */
export function joinedBefore(a: JoinOrder, b: JoinOrder): boolean {
  if (a.joinedAtMs !== b.joinedAtMs) {
    return a.joinedAtMs < b.joinedAtMs;
  }
  return a.uid < b.uid;
}

/** 購入した人がいるルームで、購入者（`adFreeSponsor`）をどうするか */
export interface SponsorAfterPurchaseInput {
  /** いまの購入者（いなければ null） */
  current: AdFreeSponsor | null;
  /** 購入した人（uid・ルームのメンバーの表示名・参加日時） */
  buyer: JoinOrder & { displayName: string };
  /** いまの購入者の参加日時（いまの購入者がいない・メンバーのドキュメントが無いときは null） */
  currentJoin: JoinOrder | null;
}

/**
 * 購入した後の、ルームの購入者（05 の §3「購入者がいれば最初に参加した人」・02 の §7.2「購入者が複数いる場合は最初に参加した人の名前」）。
 * - 購入者がいなければ、購入した人にする
 * - 購入した人のほうが先に参加していれば、購入した人に替える（最初に参加した購入者にそろえる）
 * - それ以外（購入した人が後から参加した・すでに購入者）は変えない
 * いまの購入者のメンバーのドキュメントが無い（退出の途中など）ときは、購入した人にする。
 * @param input いまの購入者と、購入した人
 * @returns 新しい購入者。変えないときは null
 */
export function sponsorAfterPurchase(input: SponsorAfterPurchaseInput): AdFreeSponsor | null {
  const next: AdFreeSponsor = { uid: input.buyer.uid, displayName: input.buyer.displayName };
  const { current, currentJoin } = input;
  if (current === null || currentJoin === null) {
    return isSameSponsor(current, next) ? null : next;
  }
  if (current.uid === input.buyer.uid) {
    return null;
  }
  return joinedBefore(input.buyer, currentJoin) ? next : null;
}

/** 同じ購入者か（uid と表示名が同じ） */
function isSameSponsor(a: AdFreeSponsor | null, b: AdFreeSponsor): boolean {
  return a !== null && a.uid === b.uid && a.displayName === b.displayName;
}
