import { writeFile, access } from "node:fs/promises";
import { randomBytes, webcrypto } from "node:crypto";
try {
  await access(".dev.vars");
  console.log("Existing local secrets preserved.");
  process.exit(0);
} catch {}
const pair = await webcrypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const privateKey = await webcrypto.subtle.exportKey("jwk", pair.privateKey),
  publicKey = await webcrypto.subtle.exportKey("jwk", pair.publicKey);
const lines = {
  TOKEN_SIGNING_JWK: JSON.stringify(privateKey),
  TOKEN_PUBLIC_KEYS: JSON.stringify([
    { kid: "community-p256-v1", alg: "ES256", publicKey },
  ]),
  CAPABILITY_SECRET: randomBytes(48).toString("base64url"),
  ADMIN_BOOTSTRAP_SECRET: randomBytes(48).toString("base64url"),
};
await writeFile(
  ".dev.vars",
  Object.entries(lines)
    .map(([k, v]) => `${k}='${v}'`)
    .join("\n") + "\n",
  { mode: 0o600, flag: "wx" },
);
console.log(
  "Generated local-only signing keys and bootstrap secret in ignored .dev.vars (mode 0600).",
);
