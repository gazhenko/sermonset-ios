import type { Context, Env, Row } from "./types";
import {
  APIError,
  b64,
  bool,
  command,
  encoder,
  fail,
  fields,
  json,
  now,
  one,
  rows,
  sha,
  sql,
  str,
  uid,
  unb64,
} from "./common";
export function publicJWK(value: Row): JsonWebKey {
  fields(
    value,
    ["kty", "crv", "x", "y", "ext", "key_ops"],
    ["kty", "crv", "x", "y"],
  );
  if (
    value.kty !== "EC" ||
    value.crv !== "P-256" ||
    typeof value.x !== "string" ||
    typeof value.y !== "string" ||
    unb64(value.x).length !== 32 ||
    unb64(value.y).length !== 32
  )
    fail(400, "invalid_request", "Use a P-256 public key.");
  return { kty: "EC", crv: "P-256", x: value.x, y: value.y, ext: true };
}
export async function verifyRequest(
  request: Request,
  env: Env,
  bytes: Uint8Array,
  jwk: JsonWebKey,
  accountID: string,
): Promise<void> {
  const timestamp = request.headers.get("X-Timestamp") ?? "";
  const nonce = request.headers.get("X-Nonce") ?? "";
  const signature = request.headers.get("X-Signature") ?? "";
  if (
    !/^\d{10}$/.test(timestamp) ||
    Math.abs(Date.now() / 1000 - Number(timestamp)) > 300 ||
    !/^[A-Za-z0-9_-]{16,128}$/.test(nonce)
  )
    fail(
      401,
      "invalid_signature",
      "Sign this request with a fresh timestamp and nonce.",
    );
  const url = new URL(request.url);
  const input = [
    "v1",
    request.method.toUpperCase(),
    url.pathname + url.search,
    accountID,
    timestamp,
    nonce,
    await sha(bytes),
  ].join("\n");
  let valid = false;
  try {
    const key = await crypto.subtle.importKey(
      "jwk",
      jwk,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const sig = unb64(signature);
    valid =
      sig.length === 64 &&
      (await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        sig,
        encoder.encode(input),
      ));
  } catch {}
  if (!valid)
    fail(
      401,
      "invalid_signature",
      "The request signature could not be verified.",
    );
  const identity =
    accountID || "registration:" + (await sha(JSON.stringify(jwk)));
  try {
    await sql(
      env,
      "INSERT INTO nonces(account_id,nonce,expires) VALUES(?,?,?)",
      identity,
      nonce,
      Math.floor(Date.now() / 1000) + 660,
    ).run();
  } catch {
    fail(
      401,
      "replay",
      "This nonce was already used. Sign the retry with a new nonce.",
    );
  }
}
export async function authenticate(
  request: Request,
  env: Env,
  bytes: Uint8Array,
): Promise<{ account: Row; session?: Row }> {
  const accountID = request.headers.get("X-Account-ID");
  if (accountID) {
    const account = await sql(
      env,
      "SELECT * FROM accounts WHERE id=?",
      accountID,
    ).first();
    if (!account) fail(401, "unauthorized", "The account is unavailable.");
    await verifyRequest(
      request,
      env,
      bytes,
      JSON.parse(account.public_key),
      accountID,
    );
    if (account.banned) fail(403, "forbidden", "This account is restricted.");
    return { account };
  }
  const cookie = request.headers
    .get("cookie")
    ?.split(";")
    .map((s) => s.trim())
    .find((s) => s.startsWith("community_session="))
    ?.slice(18);
  if (!cookie) fail(401, "unauthorized", "Sign in to continue.");
  const session = await sql(
    env,
    "SELECT s.*,a.banned FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.hash=? AND s.expires>?",
    await sha(cookie),
    Math.floor(Date.now() / 1000),
  ).first();
  if (!session) fail(401, "unauthorized", "Link your browser again.");
  if (session.banned) fail(403, "forbidden", "This account is restricted.");
  if (
    !["GET", "HEAD"].includes(request.method) &&
    (request.headers.get("Origin") !== new URL(env.PUBLIC_BASE_URL).origin ||
      request.headers.get("X-CSRF-Token") !== session.csrf)
  )
    fail(403, "forbidden", "Refresh this browser session and try again.");
  return {
    account: await one(
      env,
      "SELECT * FROM accounts WHERE id=?",
      session.account_id,
    ),
    session,
  };
}
export async function requireRole(
  c: Context,
  role: "staff" | "moderator" | "admin",
  churchID = "",
): Promise<void> {
  const allowed =
    role === "staff"
      ? ["churchStaff", "admin"]
      : role === "moderator"
        ? ["moderator", "admin"]
        : ["admin"];
  const matches = await rows(
    c.env,
    "SELECT role,church_id FROM roles WHERE account_id=?",
    c.account.id,
  );
  if (
    !matches.some(
      (r) =>
        allowed.includes(r.role) &&
        (role !== "staff" || r.role === "admin" || r.church_id === churchID),
    )
  )
    fail(403, "forbidden", "This action requires an authorized role.");
  if (role === "staff") {
    const church = await one(
      c.env,
      "SELECT verified FROM churches WHERE id=?",
      churchID,
    );
    if (!church.verified)
      fail(403, "forbidden", "This church must be verified first.");
  }
}
export async function blocked(
  env: Env,
  a: string,
  b: string,
): Promise<boolean> {
  return !!(await sql(
    env,
    "SELECT 1 FROM blocks WHERE (account_id=? AND blocked_id=?) OR (account_id=? AND blocked_id=?)",
    a,
    b,
    b,
    a,
  ).first());
}
export async function profile(env: Env, account: Row): Promise<Row> {
  return {
    id: account.id,
    displayName: account.display_name,
    avatarStyle: account.avatar_style,
    journeyOptIn: !!account.journey_opt_in,
    journeyCity: account.journey_city,
    creditOptIn: !!account.credit_opt_in,
    roles: (
      await rows(
        env,
        "SELECT role,church_id FROM roles WHERE account_id=? ORDER BY role,church_id",
        account.id,
      )
    ).map((r) => ({ role: r.role, churchID: r.church_id || null })),
  };
}
export async function hmac(env: Env, value: string): Promise<string> {
  if (!env.CAPABILITY_SECRET || env.CAPABILITY_SECRET.length < 32)
    fail(503, "not_configured", "Media signing is not configured.");
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(env.CAPABILITY_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return b64(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(value)),
    ),
  );
}
export async function capability(
  env: Env,
  kind: string,
  id: string,
  expires: number,
): Promise<string> {
  return `${expires}.${await hmac(env, `${kind}\n${id}\n${expires}`)}`;
}
export async function checkCapability(
  env: Env,
  kind: string,
  id: string,
  token: string | null,
): Promise<void> {
  const [expires, signature, ...rest] = (token ?? "").split(".");
  if (
    rest.length ||
    !/^\d{10}$/.test(expires) ||
    Number(expires) < Date.now() / 1000 ||
    !(await constantEqual(
      signature,
      await hmac(env, `${kind}\n${id}\n${expires}`),
    ))
  )
    fail(401, "unauthorized", "This media link expired. Request a fresh link.");
}
export async function constantEqual(
  a: string | undefined,
  b: string,
): Promise<boolean> {
  if (!a) return false;
  return (await sha(a)) === (await sha(b));
}
export async function signingKeys(env: Env): Promise<Row[]> {
  if (!env.TOKEN_PUBLIC_KEYS)
    fail(503, "not_configured", "Token verification keys are not configured.");
  try {
    const keys = JSON.parse(env.TOKEN_PUBLIC_KEYS);
    if (!Array.isArray(keys) || !keys.length) throw 0;
    return keys.map((k) => ({
      kid: str(k.kid, 100),
      alg: "ES256",
      publicKey: publicJWK(k.publicKey),
    }));
  } catch (e) {
    if (e instanceof APIError) throw e;
    fail(503, "not_configured", "Token verification keys are not configured.");
  }
}
export async function signToken(
  env: Env,
  typ: "offer+jwt" | "service+jwt",
  payload: Row,
): Promise<string> {
  if (!env.TOKEN_SIGNING_JWK)
    fail(503, "not_configured", "Token signing is not configured.");
  const header = b64(
    encoder.encode(
      JSON.stringify({ alg: "ES256", kid: env.TOKEN_KEY_ID, typ }),
    ),
  );
  const body = b64(
    encoder.encode(
      JSON.stringify({ v: 1, aud: env.PUBLIC_BASE_URL, ...payload }),
    ),
  );
  const key = await crypto.subtle.importKey(
    "jwk",
    JSON.parse(env.TOKEN_SIGNING_JWK),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const data = header + "." + body;
  return (
    data +
    "." +
    b64(
      new Uint8Array(
        await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          key,
          encoder.encode(data),
        ),
      ),
    )
  );
}
export async function verifyToken(
  env: Env,
  token: unknown,
  typ: "offer+jwt" | "service+jwt",
): Promise<Row> {
  try {
    if (typeof token !== "string" || token.length > 8000) throw 0;
    const parts = token.split(".");
    if (parts.length !== 3) throw 0;
    const header = JSON.parse(new TextDecoder().decode(unb64(parts[0])));
    const payload = JSON.parse(new TextDecoder().decode(unb64(parts[1])));
    const keys = await signingKeys(env);
    const found = keys.find((k) => k.kid === header.kid);
    if (
      header.alg !== "ES256" ||
      header.typ !== typ ||
      !found ||
      payload.v !== 1 ||
      payload.aud !== env.PUBLIC_BASE_URL ||
      !Number.isFinite(payload.exp) ||
      payload.exp <= Date.now() / 1000
    )
      throw 0;
    const key = await crypto.subtle.importKey(
      "jwk",
      found.publicKey,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    const sig = unb64(parts[2]);
    if (
      sig.length !== 64 ||
      !(await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        sig,
        encoder.encode(parts[0] + "." + parts[1]),
      ))
    )
      throw 0;
    return payload;
  } catch (e) {
    if (e instanceof APIError && e.status === 503) throw e;
    fail(
      401,
      "invalid_signature",
      "The token could not be verified or has expired.",
    );
  }
}
export async function register(
  request: Request,
  env: Env,
  body: Row,
  bytes: Uint8Array,
): Promise<Response> {
  fields(body, ["publicKey", "displayName", "avatarStyle"], ["publicKey"]);
  const jwk = publicJWK(body.publicKey);
  if (body.displayName !== undefined) str(body.displayName, 80);
  if (body.avatarStyle !== undefined) str(body.avatarStyle, 40);
  await verifyRequest(request, env, bytes, jwk, "");
  const fingerprint = await sha(JSON.stringify(jwk));
  const id = uid();
  await env.DB.batch([
    sql(
      env,
      "INSERT OR IGNORE INTO accounts(id,public_key,key_fingerprint,display_name,avatar_style,created_at) VALUES(?,?,?,?,?,?)",
      id,
      JSON.stringify(jwk),
      fingerprint,
      body.displayName ?? null,
      body.avatarStyle ?? "plain",
      now(),
    ),
    sql(
      env,
      "INSERT OR IGNORE INTO roles(account_id,role) SELECT id,'listener' FROM accounts WHERE key_fingerprint=?",
      fingerprint,
    ),
  ]);
  const account = await one(
    env,
    "SELECT * FROM accounts WHERE key_fingerprint=?",
    fingerprint,
  );
  if (account.banned) fail(403, "forbidden", "This account is restricted.");
  const url = new URL(request.url);
  return command(
    {
      request,
      url,
      env,
      bytes,
      body,
      account,
      key: request.headers.get("Idempotency-Key")!,
      hash: await sha(
        request.method +
          "\n" +
          url.pathname +
          url.search +
          "\n" +
          (await sha(bytes)),
      ),
    },
    { account: await profile(env, account) },
    [],
  );
}
