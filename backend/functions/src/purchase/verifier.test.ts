import { VerificationException, VerificationStatus } from "@apple/app-store-server-library";

import { REMOVE_ADS_PRODUCT_ID } from "../domain/constants";
import type { PurchaseEnvironment } from "./logic";
import { appleTransactionVerifier, verifierTryingInOrder, type EnvironmentVerifier } from "./verifier";

/** 理由つきのエラーで失敗することを確かめる */
async function expectReason(promise: Promise<unknown>, reason: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ details: { reason } });
}

/** 署名を確かめない JWS（Xcode の StoreKit のテストの形。テストで作れるのはこれだけ） */
function unsignedJws(payload: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "ES256", typ: "JWT" })}.${encode(payload)}.${Buffer.from("signature").toString("base64url")}`;
}

/** 呼ばれた環境を覚え、決めた結果を返す検証 */
function fakeVerifier(environment: PurchaseEnvironment, result: Error | { productId: string }, calls: string[]): EnvironmentVerifier {
  return {
    environment,
    verifyAndDecodeTransaction: () => {
      calls.push(environment);
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve({ ...result, transactionId: "t1", originalTransactionId: "o1" });
    },
  };
}

describe("verifierTryingInOrder（環境を順に試す）", () => {
  it("環境が違う（INVALID_ENVIRONMENT）ときだけ次の環境を試す（Production の後に Sandbox）", async () => {
    const calls: string[] = [];
    const verifier = verifierTryingInOrder([
      fakeVerifier("Production", new VerificationException(VerificationStatus.INVALID_ENVIRONMENT), calls),
      fakeVerifier("Sandbox", { productId: REMOVE_ADS_PRODUCT_ID }, calls),
    ]);
    await expect(verifier.verify("jws")).resolves.toEqual({
      productId: REMOVE_ADS_PRODUCT_ID,
      transactionId: "t1",
      originalTransactionId: "o1",
      environment: "Sandbox",
      revocationDate: undefined,
    });
    expect(calls).toEqual(["Production", "Sandbox"]);
  });

  it("署名・Bundle ID・証明書の失敗では次の環境を試さずに purchase-invalid", async () => {
    for (const status of [
      VerificationStatus.VERIFICATION_FAILURE,
      VerificationStatus.INVALID_APP_IDENTIFIER,
      VerificationStatus.INVALID_CERTIFICATE,
      VerificationStatus.INVALID_CHAIN_LENGTH,
      VerificationStatus.FAILURE,
    ]) {
      const calls: string[] = [];
      const verifier = verifierTryingInOrder([
        fakeVerifier("Production", new VerificationException(status), calls),
        fakeVerifier("Sandbox", { productId: REMOVE_ADS_PRODUCT_ID }, calls),
      ]);
      await expectReason(verifier.verify("jws"), "purchase-invalid");
      expect(calls).toEqual(["Production"]);
    }
  });

  it("一時的な失敗（失効の確認に通信できない）は purchase-verification-unavailable", async () => {
    const verifier = verifierTryingInOrder([
      fakeVerifier("Production", new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE), []),
    ]);
    await expectReason(verifier.verify("jws"), "purchase-verification-unavailable");
  });

  it("想定していない例外・すべての環境で違うときも purchase-invalid", async () => {
    await expectReason(verifierTryingInOrder([fakeVerifier("Sandbox", new Error("boom"), [])]).verify("jws"), "purchase-invalid");
    const mismatch = new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
    await expectReason(
      verifierTryingInOrder([fakeVerifier("Production", mismatch, []), fakeVerifier("Sandbox", mismatch, [])]).verify("jws"),
      "purchase-invalid",
    );
    await expectReason(verifierTryingInOrder([]).verify("jws"), "purchase-invalid");
  });
});

describe("appleTransactionVerifier（App Store Server Library）", () => {
  const bundleId = "jp.shilokuma.Dokogacha";
  const xcodePurchase = {
    bundleId,
    productId: REMOVE_ADS_PRODUCT_ID,
    transactionId: "0",
    originalTransactionId: "0",
    environment: "Xcode",
    type: "Non-Consumable",
    signedDate: 1_760_000_000_000,
  };

  it("Emulator では Xcode の StoreKit のテストの購入（署名なし）を読める", async () => {
    const verifier = appleTransactionVerifier({ bundleId, appAppleId: undefined, emulator: true });
    await expect(verifier.verify(unsignedJws(xcodePurchase))).resolves.toMatchObject({
      productId: REMOVE_ADS_PRODUCT_ID,
      environment: "Xcode",
    });
  });

  it("Emulator でも別のアプリ（Bundle ID）の購入は断る", async () => {
    const verifier = appleTransactionVerifier({ bundleId, appAppleId: undefined, emulator: true });
    await expectReason(verifier.verify(unsignedJws({ ...xcodePurchase, bundleId: "com.example.other" })), "purchase-invalid");
  });

  it("本番では Xcode の購入（App Store の証明書で署名されていない）を受け付けない", async () => {
    const verifier = appleTransactionVerifier({ bundleId, appAppleId: 1234567890, emulator: false });
    await expectReason(verifier.verify(unsignedJws(xcodePurchase)), "purchase-invalid");
    await expectReason(verifier.verify(unsignedJws({ ...xcodePurchase, environment: "Sandbox" })), "purchase-invalid");
    await expectReason(verifier.verify(unsignedJws({ ...xcodePurchase, environment: "Production" })), "purchase-invalid");
  });

  it("JWS として読めない文字列は purchase-invalid", async () => {
    const verifier = appleTransactionVerifier({ bundleId, appAppleId: undefined, emulator: true });
    await expectReason(verifier.verify("a.b.c"), "purchase-invalid");
  });
});
