// Confirms a Vitalis Pro subscription from the App Store's own signed record, never from what the app claims.
//
// The app sends Transaction.jwsRepresentation for its current entitlement. Apple signs it (ES256) with a
// certificate chain ending at Apple Root CA - G3, pinned below; Apple's official library checks the signature,
// the chain, revocation, the bundle id and the environment. We then also require the product to be one of ours,
// not revoked, not expired, and bought by this account (appAccountToken is set to the user id at purchase).
// Xcode's local StoreKit test store is deliberately not accepted: its records aren't signed by Apple.

import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";

/** Apple Root CA - G3 (DER), SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79. */
const APPLE_ROOT_CA_G3 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const BUNDLE_ID = "com.omsilwal.NutriCorePrimal";
export const PRO_PRODUCTS = new Set([`${BUNDLE_ID}.pro.monthly`, `${BUNDLE_ID}.pro.annual`]);

const roots = [Buffer.from(APPLE_ROOT_CA_G3, "base64")];
/** The numeric App Store id (App Store Connect › App Information); required to verify Production records. */
const appAppleId = Number(Deno.env.get("APPLE_APP_ID") ?? "") || undefined;

const verifiers: SignedDataVerifier[] = [
  ...(appAppleId ? [new SignedDataVerifier(roots, true, Environment.PRODUCTION, BUNDLE_ID, appAppleId)] : []),
  // TestFlight and sandbox testers.
  new SignedDataVerifier(roots, true, Environment.SANDBOX, BUNDLE_ID),
];

export type Entitlement = { productId: string; originalTransactionId: string; expiresAt: Date; environment: string };

/** The verified Pro entitlement in this JWS for this user, or null. Never throws. */
export async function verifyPro(jws: string | undefined, userId: string, now = new Date()): Promise<Entitlement | null> {
  if (!jws || jws.split(".").length !== 3) return null;
  for (const verifier of verifiers) {
    try {
      const t = await verifier.verifyAndDecodeTransaction(jws);
      if (!t.productId || !PRO_PRODUCTS.has(t.productId)) return null;
      if (t.revocationDate) return null;
      if (!t.expiresDate || t.expiresDate <= now.getTime()) return null;
      if (t.appAccountToken && t.appAccountToken.toLowerCase() !== userId.toLowerCase()) return null;
      return {
        productId: t.productId,
        originalTransactionId: t.originalTransactionId ?? "",
        expiresAt: new Date(t.expiresDate),
        environment: String(t.environment ?? ""),
      };
    } catch {
      // Not valid for this environment; try the next one.
    }
  }
  return null;
}
