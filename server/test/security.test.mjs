import { test } from "node:test";
import assert from "node:assert/strict";
import { harness } from "./harness.mjs";
import { signedRequest } from "../scripts/client.mjs";
test("signed device identity and registration recovery", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Listener");
  assert.equal((await h.call(who, "GET", "/v1/me")).account.id, who.id);
  const original = who.id;
  who.id = "";
  assert.equal(
    (await h.call(who, "POST", "/v1/accounts", { publicKey: who.publicKey }))
      .account.id,
    original,
  );
});
test("signatures cover method, exact query, body, account and replay nonce; clocks are bounded", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Listener");
  let req = await signedRequest(who, "GET", "/v1/me");
  assert.equal((await h.fetch("/v1/me", req)).status, 200);
  assert.equal((await h.fetch("/v1/me", req)).status, 401);
  req = await signedRequest(who, "GET", "/v1/me");
  assert.equal((await h.fetch("/v1/me?injected=1", req)).status, 401);
  req = await signedRequest(who, "PATCH", "/v1/me", { displayName: "A" });
  req.body = JSON.stringify({ displayName: "B" });
  assert.equal((await h.fetch("/v1/me", req)).status, 401);
  assert.equal(
    (
      await h.raw(who, "GET", "/v1/me", undefined, {
        timestamp: Math.floor(Date.now() / 1000) - 301,
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await h.raw(who, "GET", "/v1/me", undefined, {
        timestamp: Math.floor(Date.now() / 1000) + 301,
      })
    ).status,
    401,
  );
});
test("registration uses JSON errors for invalid signatures and rejects changed idempotent request bodies", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Identity");
  who.id = "";
  const key = crypto.randomUUID();
  const body = { publicKey: who.publicKey, displayName: "Identity" };
  const first = await h.call(who, "POST", "/v1/accounts", body, { key });
  assert.deepEqual(
    await h.call(who, "POST", "/v1/accounts", body, { key }),
    first,
  );
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/accounts",
        { ...body, displayName: "Other" },
        { key },
      )
    ).status,
    409,
  );
  const request = await signedRequest(who, "POST", "/v1/accounts", body);
  request.headers["X-Signature"] = "A".repeat(86);
  const rejected = await h.fetch("/v1/accounts", request);
  assert.equal(rejected.status, 401);
  assert.equal((await rejected.json()).error.code, "invalid_signature");
});
