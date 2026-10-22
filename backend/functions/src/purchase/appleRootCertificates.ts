/**
 * App Store が署名に使う証明書の根（ルート証明書）。署名付きトランザクション（JWS）の証明書の連なりをここまでたどって確かめる。
 *
 * Apple が公開している「Apple Root CA - G3」（https://www.apple.com/certificateauthority/AppleRootCA-G3.cer）の PEM。
 * 公開の証明書（秘密鍵ではない）なので、リポジトリに置いてよい。macOS の SystemRootCertificates.keychain にある同じ証明書と
 * 一致することを確かめて写した（SHA-256 の指紋は `APPLE_ROOT_CA_G3_SHA256`。Jest で確かめる）。
 * 有効期限は 2039-04-30。Apple が根を替えたら、ここに足す。
 */

/** Apple Root CA - G3 の SHA-256 の指紋（16 進・大文字・区切りなし） */
export const APPLE_ROOT_CA_G3_SHA256 = "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179";

/** Apple Root CA - G3（PEM） */
export const APPLE_ROOT_CA_G3_PEM = `
-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----
`;

/** 検証に使うルート証明書（DER）の一覧 */
export function appleRootCertificates(): Buffer[] {
  return [pemToDer(APPLE_ROOT_CA_G3_PEM)];
}

/**
 * PEM の証明書を DER にする。
 * @param pem PEM（`-----BEGIN CERTIFICATE-----` で囲んだ base64）
 * @returns DER
 */
export function pemToDer(pem: string): Buffer {
  const body = pem
    .replace(/-----BEGIN CERTIFICATE-----/u, "")
    .replace(/-----END CERTIFICATE-----/u, "")
    .replace(/\s+/gu, "");
  return Buffer.from(body, "base64");
}
