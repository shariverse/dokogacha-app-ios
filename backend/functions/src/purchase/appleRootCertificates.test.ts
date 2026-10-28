import { createHash, X509Certificate } from "node:crypto";

import { APPLE_ROOT_CA_G3_PEM, APPLE_ROOT_CA_G3_SHA256, appleRootCertificates, pemToDer } from "./appleRootCertificates";

describe("appleRootCertificates", () => {
  it("同梱の証明書は Apple Root CA - G3（公開の証明書）で、指紋が一致する", () => {
    const [der] = appleRootCertificates();
    expect(der).toBeDefined();
    const certificate = new X509Certificate(der ?? Buffer.alloc(0));
    expect(certificate.subject).toContain("CN=Apple Root CA - G3");
    expect(certificate.issuer).toBe(certificate.subject);
    expect(createHash("sha256").update(der ?? Buffer.alloc(0)).digest("hex").toUpperCase()).toBe(APPLE_ROOT_CA_G3_SHA256);
    expect(certificate.fingerprint256.replaceAll(":", "")).toBe(APPLE_ROOT_CA_G3_SHA256);
  });

  it("秘密鍵を含まない（証明書だけ）", () => {
    expect(APPLE_ROOT_CA_G3_PEM).not.toMatch(/PRIVATE KEY/u);
    expect(pemToDer(APPLE_ROOT_CA_G3_PEM).length).toBeGreaterThan(0);
  });
});
