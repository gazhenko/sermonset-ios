import { createHash, randomUUID, webcrypto } from "node:crypto";
export const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
export async function identity() {
  const keys = await webcrypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  return {
    keys,
    publicKey: await webcrypto.subtle.exportKey("jwk", keys.publicKey),
    id: "",
  };
}
export async function signedRequest(who, method, path, body, options = {}) {
  const bytes =
    body === undefined ? Buffer.alloc(0) : Buffer.from(JSON.stringify(body));
  const timestamp = String(options.timestamp ?? Math.floor(Date.now() / 1000)),
    nonce = options.nonce ?? randomUUID();
  const canonical = [
    "v1",
    method,
    path,
    who.id,
    timestamp,
    nonce,
    hash(bytes),
  ].join("\n");
  const signature = Buffer.from(
    await webcrypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      who.keys.privateKey,
      new TextEncoder().encode(canonical),
    ),
  ).toString("base64url");
  const headers = {
    "X-Timestamp": timestamp,
    "X-Nonce": nonce,
    "X-Signature": signature,
    "Idempotency-Key": options.key ?? randomUUID(),
  };
  if (who.id) headers["X-Account-ID"] = who.id;
  if (body !== undefined) headers["content-type"] = "application/json";
  return { method, headers, body: body === undefined ? undefined : bytes };
}
export function apiClient(dispatch, base = "http://127.0.0.1:8787") {
  async function raw(who, method, path, body, options) {
    return dispatch(
      base + path,
      await signedRequest(who, method, path, body, options),
    );
  }
  async function call(who, method, path, body, options) {
    const response = await raw(who, method, path, body, options);
    const result = await response.json();
    if (!response.ok)
      throw Error(
        `${method} ${path}: ${response.status} ${JSON.stringify(result)}`,
      );
    return result;
  }
  async function account(name) {
    const who = await identity();
    const result = await call(who, "POST", "/v1/accounts", {
      publicKey: who.publicKey,
      displayName: name,
    });
    who.id = result.account.id;
    return who;
  }
  return { raw, call, account };
}
