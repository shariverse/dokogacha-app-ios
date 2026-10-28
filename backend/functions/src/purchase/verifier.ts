/**
 * StoreKit 2 の署名付きトランザクション（JWS）を確かめる窓口（05 の §1「サーバー検証は App Store Server Library（Node）」）。
 *
 * `verifyPurchase` の処理（`service.ts`）はこの interface だけを見る。本物（`appleTransactionVerifier`）は Apple の証明書で
 * 署名を確かめるので、Jest・Emulator のテストでは差し替える（App Store が署名したトランザクションはテストで作れない）。
 */
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

import { appError } from "../errors";
import { appleRootCertificates } from "./appleRootCertificates";
import { verificationEnvironments, type PurchaseEnvironment, type VerifiedTransaction, type VerificationSettings } from "./logic";

/** 署名付きトランザクションを確かめる窓口 */
export interface TransactionVerifier {
  /**
   * 署名と、アプリ（Bundle ID）・環境が正しいか確かめて、中身を返す。
   * @param signedTransaction StoreKit 2 の `jwsRepresentation`
   * @returns 確かめたトランザクション
   * @throws `purchase-invalid`（確かめられなかった）・`purchase-verification-unavailable`（一時的に確かめられなかった）
   */
  verify(signedTransaction: string): Promise<VerifiedTransaction>;
}

/** 環境ごとに署名を確かめる処理（App Store Server Library の `SignedDataVerifier` の必要なところだけ） */
export interface EnvironmentVerifier {
  /** 確かめる環境 */
  environment: PurchaseEnvironment;
  /** 署名を確かめて中身を返す（`SignedDataVerifier.verifyAndDecodeTransaction`） */
  verifyAndDecodeTransaction(signedTransaction: string): Promise<{
    productId?: string;
    transactionId?: string;
    originalTransactionId?: string;
    revocationDate?: number;
  }>;
}

/** 本物の検証の設定（Functions のパラメータから作る） */
export interface AppleVerifierSettings extends VerificationSettings {
  /** アプリの Bundle ID */
  bundleId: string;
}

/** 環境の文字列を App Store Server Library の値にする */
const LIBRARY_ENVIRONMENTS: Record<PurchaseEnvironment, Environment> = {
  Production: Environment.PRODUCTION,
  Sandbox: Environment.SANDBOX,
  Xcode: Environment.XCODE,
};

/**
 * App Store Server Library で確かめる窓口を作る。
 * - ルート証明書は同梱の Apple Root CA - G3（公開の証明書。`appleRootCertificates.ts`）
 * - Emulator 以外では、証明書の失効もオンラインで確かめる（`enableOnlineChecks`）
 * - 環境は `verificationEnvironments` の順に試す
 * @param settings 設定
 * @returns 窓口
 */
export function appleTransactionVerifier(settings: AppleVerifierSettings): TransactionVerifier {
  const roots = appleRootCertificates();
  const verifiers = verificationEnvironments(settings).map((environment): EnvironmentVerifier => {
    const verifier = new SignedDataVerifier(
      roots,
      !settings.emulator,
      LIBRARY_ENVIRONMENTS[environment],
      settings.bundleId,
      environment === "Production" ? settings.appAppleId : undefined,
    );
    return { environment, verifyAndDecodeTransaction: (signed) => verifier.verifyAndDecodeTransaction(signed) };
  });
  return verifierTryingInOrder(verifiers);
}

/**
 * 環境を前から順に試して確かめる窓口。
 * 環境が違う（`INVALID_ENVIRONMENT`）ときだけ次の環境を試し、ほかの失敗（署名・Bundle ID・証明書）はそこで断る。
 * 一時的な失敗（`RETRYABLE_VERIFICATION_FAILURE`。失効の確認に通信できなかった）は `purchase-verification-unavailable`。
 * @param verifiers 環境ごとの検証（試す順）
 * @returns 窓口
 */
export function verifierTryingInOrder(verifiers: readonly EnvironmentVerifier[]): TransactionVerifier {
  return {
    async verify(signedTransaction: string): Promise<VerifiedTransaction> {
      for (const verifier of verifiers) {
        try {
          const payload = await verifier.verifyAndDecodeTransaction(signedTransaction);
          return {
            productId: payload.productId,
            transactionId: payload.transactionId,
            originalTransactionId: payload.originalTransactionId,
            environment: verifier.environment,
            revocationDate: payload.revocationDate,
          };
        } catch (error) {
          if (error instanceof VerificationException && error.status === VerificationStatus.INVALID_ENVIRONMENT) {
            continue;
          }
          if (error instanceof VerificationException && error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
            throw appError("purchase-verification-unavailable");
          }
          throw appError("purchase-invalid");
        }
      }
      throw appError("purchase-invalid");
    },
  };
}
