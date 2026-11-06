// deno test --allow-env --allow-read supabase/functions/_shared/apple_entitlement_test.ts
import { assertEquals } from "jsr:@std/assert@1.0.13";
import { verifyPro } from "./apple_entitlement.ts";

const b64url = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");

Deno.test("nothing, garbage and unsigned records are not Pro", async () => {
  assertEquals(await verifyPro(undefined, "u1"), null);
  assertEquals(await verifyPro("garbage", "u1"), null);
  const payload = { productId: "com.omsilwal.NutriCorePrimal.pro.annual", bundleId: "com.omsilwal.NutriCorePrimal",
    expiresDate: Date.now() + 86_400_000, environment: "Sandbox", originalTransactionId: "1" };
  assertEquals(await verifyPro(`${b64url({ alg: "none" })}.${b64url(payload)}.`, "u1"), null);
});

Deno.test("a forged record with a self-made certificate chain is not Pro", async () => {
  // Signed with a fresh key and an invented x5c chain: looks right, isn't Apple's.
  const key = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
  const header = b64url({ alg: "ES256", x5c: ["MIIBfake1", "MIIBfake2", "MIIBfake3"] });
  const body = b64url({ productId: "com.omsilwal.NutriCorePrimal.pro.annual", bundleId: "com.omsilwal.NutriCorePrimal",
    expiresDate: Date.now() + 86_400_000, environment: "Sandbox", originalTransactionId: "2", signedDate: Date.now() });
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key.privateKey,
    new TextEncoder().encode(`${header}.${body}`)));
  const s = btoa(String.fromCharCode(...sig)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  assertEquals(await verifyPro(`${header}.${body}.${s}`, "u1"), null);
});
