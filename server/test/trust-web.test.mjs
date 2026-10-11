import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID, webcrypto } from "node:crypto";
import { harness, metadata, testBindings } from "./harness.mjs";
import { hash } from "../scripts/client.mjs";
import { readFile } from "node:fs/promises";
const audioBytes = await readFile(
  "../Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/peace-in-the-storm.m4a",
);
const audio = {
  byteCount: audioBytes.length,
  duration: 101.599667,
  checksumSHA256: hash(audioBytes),
  sourceChecksumSHA256: "a".repeat(64),
  contentType: "audio/mp4",
  trimStart: 1,
  trimEnd: 102.599667,
};
async function service(h, staff, extra = {}) {
  return h.call(
    staff,
    "POST",
    "/v1/portal/churches/sample-church-west/services",
    {
      service: "Sunday morning",
      startsAt: new Date(Date.now() - 60000).toISOString(),
      expiresAt: new Date(Date.now() + 86400000).toISOString(),
      recordingAllowed: true,
      publicSharingAllowed: true,
      reviewRequired: false,
      ...extra,
    },
  );
}
async function verifyOffline(token, typ, keys) {
  const [header, payload, signature] = token.split(".");
  const h = JSON.parse(Buffer.from(header, "base64url")),
    p = JSON.parse(Buffer.from(payload, "base64url"));
  assert.equal(h.alg, "ES256");
  assert.equal(h.typ, typ);
  const found = keys.find((k) => k.kid === h.kid);
  assert(found);
  const key = await webcrypto.subtle.importKey(
    "jwk",
    found.publicKey,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  assert(
    await webcrypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      Buffer.from(signature, "base64url"),
      Buffer.from(header + "." + payload),
    ),
  );
  assert.equal(p.v, 1);
  assert.equal(p.aud, testBindings.PUBLIC_BASE_URL);
  return p;
}
test("offer and service tokens verify offline against published P-256 keys; service printing is role-gated", async (t) => {
  const h = await harness();
  t.after(h.close);
  const staff = await h.account("Staff"),
    who = await h.account("Listener");
  await h.staff(staff);
  const svc = await service(h, staff);
  const keys = (await (await h.fetch("/v1/keys")).json()).keys;
  const payload = await verifyOffline(svc.token, "service+jwt", keys);
  assert.equal(payload.church, "sample-church-west");
  assert.equal(payload.publicSharingAllowed, true);
  const card = await h.call(who, "POST", "/v1/sermons/sample-open-hands/keep", {
    source: "discover",
  });
  const offer = await h.call(who, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.cardID,
    cardVersion: 1,
  });
  assert.equal(
    (await verifyOffline(offer.token, "offer+jwt", keys)).offerID,
    offer.offerID,
  );
  assert.equal(
    (await h.raw(who, "GET", new URL(svc.printURL).pathname)).status,
    403,
  );
  const print = await h.raw(staff, "GET", new URL(svc.printURL).pathname);
  assert.equal(print.status, 200);
  assert((await print.text()).includes(svc.token));
  assert(
    (await print.headers.get("content-security-policy")).includes(
      "frame-ancestors 'none'",
    ),
  );
});
test("verified QR grants auto-publish; revocation disables issued audio and blocks restoration", async (t) => {
  const h = await harness();
  t.after(h.close);
  const staff = await h.account("Staff"),
    who = await h.account("Publisher");
  await h.staff(staff);
  await h.admin(staff);
  const svc = await service(h, staff);
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      service: "Sunday morning",
      rightsBasis: "serviceQR",
      serviceToken: svc.token,
      audio,
    }),
  );
  assert.equal(
    (
      await h.mf.dispatchFetch(pub.uploadURL, {
        method: "PUT",
        headers: { "content-type": "audio/mp4" },
        body: audioBytes,
      })
    ).status,
    200,
  );
  await h.call(
    who,
    "POST",
    `/v1/publications/${pub.publicationID}/complete`,
    {},
  );
  assert.equal(
    (await h.call(who, "GET", `/v1/publications/${pub.publicationID}`))
      .publication.state,
    "published",
  );
  const link = await h.call(
    who,
    "POST",
    `/v1/sermons/${pub.sermonID}/audio-url`,
    {},
  );
  const streamed = await h.mf.dispatchFetch(link.url);
  assert.equal(streamed.status, 200);
  await streamed.arrayBuffer();
  await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/services/${svc.serviceID}/revoke`,
    {},
  );
  assert.equal((await h.mf.dispatchFetch(link.url)).status, 410);
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          service: "Sunday morning",
          rightsBasis: "serviceQR",
          serviceToken: svc.token,
          audio,
        }),
      )
    ).status,
    403,
  );
  await h.call(staff, "POST", "/v1/moderation/actions", {
    targetType: "audio",
    targetID: pub.audioAssetID,
    action: "remove",
    reason: "Withdrawn QR rights",
  });
  assert.equal(
    (
      await h.raw(staff, "POST", "/v1/moderation/actions", {
        targetType: "audio",
        targetID: pub.audioAssetID,
        action: "restore",
        reason: "Must fail after revocation",
      })
    ).status,
    403,
  );
});
test("recording-only QR never grants redistribution and review-required QR stays pending", async (t) => {
  const h = await harness();
  t.after(h.close);
  const staff = await h.account("Staff"),
    who = await h.account("Publisher");
  await h.staff(staff);
  let svc = await service(h, staff, { publicSharingAllowed: false });
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          service: "Sunday morning",
          rightsBasis: "serviceQR",
          serviceToken: svc.token,
          audio,
        }),
      )
    ).status,
    403,
  );
  svc = await service(h, staff, { reviewRequired: true });
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      service: "Sunday morning",
      rightsBasis: "serviceQR",
      serviceToken: svc.token,
      audio,
    }),
  );
  assert.equal(
    (
      await h.mf.dispatchFetch(pub.uploadURL, {
        method: "PUT",
        headers: { "content-type": "audio/mp4" },
        body: audioBytes,
      })
    ).status,
    200,
  );
  await h.call(
    who,
    "POST",
    `/v1/publications/${pub.publicationID}/complete`,
    {},
  );
  assert.equal(
    (await h.call(who, "GET", `/v1/publications/${pub.publicationID}`))
      .publication.state,
    "pendingRights",
  );
  const tampered = svc.token.slice(0, -4) + "AAAA";
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          service: "Sunday morning",
          rightsBasis: "serviceQR",
          serviceToken: tampered,
          audio,
        }),
      )
    ).status,
    401,
  );
});
test("single-use browser link codes yield HttpOnly strict cookies; every web mutation enforces CSRF/origin", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Browser");
  const link = await h.call(who, "POST", "/v1/web/link-codes", {});
  const options = {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: testBindings.PUBLIC_BASE_URL,
    },
    body: JSON.stringify({ code: link.code }),
  };
  const response = await h.fetch("/v1/web/session", options);
  assert.equal(response.status, 200);
  const data = await response.json(),
    cookie = response.headers.get("set-cookie").split(";")[0];
  assert(response.headers.get("set-cookie").includes("HttpOnly"));
  assert(response.headers.get("set-cookie").includes("SameSite=Strict"));
  assert.equal((await h.fetch("/v1/web/session", options)).status, 401);
  assert.equal((await h.fetch("/v1/me", { headers: { cookie } })).status, 200);
  let headers = {
    cookie,
    "content-type": "application/json",
    "Idempotency-Key": randomUUID(),
    origin: testBindings.PUBLIC_BASE_URL,
  };
  assert.equal(
    (
      await h.fetch("/v1/me", {
        method: "PATCH",
        headers,
        body: JSON.stringify({ displayName: "Changed" }),
      })
    ).status,
    403,
  );
  headers["X-CSRF-Token"] = data.csrfToken;
  headers.origin = "https://attacker.invalid";
  assert.equal(
    (
      await h.fetch("/v1/me", {
        method: "PATCH",
        headers,
        body: JSON.stringify({ displayName: "Changed" }),
      })
    ).status,
    403,
  );
  headers.origin = testBindings.PUBLIC_BASE_URL;
  assert.equal(
    (
      await h.fetch("/v1/me", {
        method: "PATCH",
        headers,
        body: JSON.stringify({ displayName: "Changed" }),
      })
    ).status,
    200,
  );
  delete headers["Idempotency-Key"];
  assert.equal(
    (await h.fetch("/v1/web/session", { method: "DELETE", headers })).status,
    200,
  );
  assert.equal((await h.fetch("/v1/me", { headers: { cookie } })).status, 401);
});
test("admin bootstrap is a secret-only role path; ordinary listeners cannot use moderation/staff APIs", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Listener");
  assert.equal((await h.raw(who, "GET", "/v1/moderation/queue")).status, 403);
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/portal/churches/sample-church-west/services",
        { service: "Bad" },
      )
    ).status,
    403,
  );
  const response = await h.fetch("/v1/web/session", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: testBindings.PUBLIC_BASE_URL,
    },
    body: JSON.stringify({
      bootstrapSecret: testBindings.ADMIN_BOOTSTRAP_SECRET,
      accountID: who.id,
    }),
  });
  assert.equal(response.status, 200);
  assert((await response.json()).account.roles.some((r) => r.role === "admin"));
  assert.equal((await h.raw(who, "GET", "/v1/moderation/queue")).status, 200);
});
test("claim review grants staff role, corrections/profile are scoped, and moderation is audited/appealable", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Applicant"),
    mod = await h.account("Admin");
  await h.admin(mod);
  const claim = await h.call(who, "POST", "/v1/church-claims", {
    name: "Fictional new church",
    website: "https://example.invalid",
    role: "Fictional pastor",
    evidence: "Fixture verification evidence",
  });
  assert.equal(
    (await h.call(mod, "GET", "/v1/moderation/queue?kind=claims")).items.length,
    1,
  );
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "claim",
    targetID: claim.claimID,
    action: "approve",
    reason: "Verified fixture claim",
  });
  const churches = (await h.call(who, "GET", "/v1/portal/churches")).items;
  assert.equal(churches.length, 1);
  await h.call(who, "PATCH", `/v1/portal/churches/${churches[0].id}`, {
    city: "Toronto",
    creditPolicy: "named",
  });
  assert.equal(
    (
      await h.raw(who, "PATCH", "/v1/portal/churches/sample-church-west", {
        city: "Wrong",
      })
    ).status,
    403,
  );
  const pub = await h.call(who, "POST", "/v1/publications", metadata());
  const rejected = await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "reject",
    reason: "Wrong attribution",
  });
  const appeal = await h.call(who, "POST", "/v1/appeals", {
    actionID: rejected.actionID,
    reason: "Please review",
  });
  assert.equal(
    (await h.call(mod, "GET", "/v1/moderation/queue?kind=appeals")).items[0].id,
    appeal.appealID,
  );
  assert.equal(
    (
      await h.raw(mod, "POST", "/v1/appeals", {
        actionID: rejected.actionID,
        reason: "Not affected",
      })
    ).status,
    403,
  );
  assert(
    (await h.call(mod, "GET", "/v1/moderation/audit")).items.some(
      (a) => a.id === rejected.actionID,
    ),
  );
});
test("reports, bans, unbans and inbox reads are authorized and audited", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Reporter"),
    mod = await h.account("Admin");
  await h.admin(mod);
  const report = await h.call(who, "POST", "/v1/reports", {
    targetType: "sermon",
    targetID: "sample-peace-in-the-storm",
    reason: "privacy",
    timestamp: 30,
    details: "Explicit fictional report",
  });
  const queued = (await h.call(mod, "GET", "/v1/moderation/queue?kind=reports"))
    .items[0];
  assert.equal(queued.id, report.reportID);
  assert.equal(queued.timestamp, 30);
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "report",
    targetID: report.reportID,
    action: "resolve",
    reason: "Reviewed",
  });
  const inbox = (await h.call(who, "GET", "/v1/inbox")).items;
  await h.call(who, "POST", `/v1/inbox/${inbox[0].id}/read`, {});
  assert.equal((await h.call(who, "GET", "/v1/inbox")).items[0].read, true);
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "account",
    targetID: who.id,
    action: "ban",
    reason: "Fictional abuse",
  });
  assert.equal((await h.raw(who, "GET", "/v1/me")).status, 403);
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "account",
    targetID: who.id,
    action: "unban",
    reason: "Restored",
  });
  assert.equal((await h.raw(who, "GET", "/v1/me")).status, 200);
});
test("share PNG upload is bounded and checksum-verified; templates escape public copy and use configured scheme", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Share");
  await h.admin(who);
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ title: '<script>alert("x")</script>' }),
  );
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Metadata fixture",
  });
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jC0kAAAAASUVORK5CYII=",
    "base64",
  );
  const share = await h.call(who, "POST", "/v1/shares", {
    sermonID: pub.sermonID,
    byteCount: png.length,
    checksumSHA256: hash(png),
  });
  assert.equal(
    (
      await h.mf.dispatchFetch(share.uploadURL, {
        method: "PUT",
        headers: { "content-type": "image/png" },
        body: png,
      })
    ).status,
    200,
  );
  const page = await h.fetch(`/s/${share.shareID}`);
  assert.equal(page.status, 200);
  const html = await page.text();
  assert(html.includes("&lt;script&gt;"));
  assert(!html.includes("<script>alert"));
  assert(html.includes("testcommunity://sermon/"));
  assert.equal(
    (await h.fetch(`/v1/share-images/${share.shareID}`)).headers.get(
      "content-type",
    ),
    "image/png",
  );
  assert.equal((await h.fetch("/portal")).status, 200);
  assert.equal((await h.fetch("/moderation")).status, 200);
});
test("account deletion removes owned state and media, anonymizes credit and retains other owners history", async (t) => {
  const h = await harness();
  t.after(h.close);
  const a = await h.account("Delete"),
    b = await h.account("Keep"),
    staff = await h.account("Staff");
  await h.staff(staff);
  const pub = await h.call(
    a,
    "POST",
    "/v1/publications",
    metadata({ rightsBasis: "churchReview", audio }),
  );
  assert.equal(
    (
      await h.mf.dispatchFetch(pub.uploadURL, {
        method: "PUT",
        headers: { "content-type": "audio/mp4" },
        body: audioBytes,
      })
    ).status,
    200,
  );
  await h.call(a, "POST", `/v1/publications/${pub.publicationID}/complete`, {});
  await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/publications/${pub.publicationID}/decision`,
    { decision: "approve", reason: "Fixture authorized" },
  );
  await h.call(b, "POST", `/v1/sermons/${pub.sermonID}/keep`, {
    source: "shared",
  });
  await h.call(a, "DELETE", "/v1/me");
  assert.equal((await h.raw(a, "GET", "/v1/me")).status, 401);
  assert.equal(
    await h.db
      .prepare("SELECT 1 FROM contributors WHERE account_id=?")
      .bind(a.id)
      .first(),
    null,
  );
  assert.equal((await h.call(b, "GET", "/v1/cards")).items.length, 1);
  assert.equal(
    (await h.call(b, "GET", "/v1/library")).items[0].sermonID,
    pub.sermonID,
  );
  assert.equal(
    (await h.raw(b, "POST", `/v1/sermons/${pub.sermonID}/audio-url`, {}))
      .status,
    410,
  );
  assert.equal(
    await (
      await h.mf.getR2Bucket("AUDIO")
    ).head(`private/audio/${pub.audioAssetID}`),
    null,
  );
  assert.equal(
    (await h.db.prepare("SELECT COUNT(*) AS n FROM deletion_jobs").first()).n,
    0,
  );
});
test("review queues expose only submitted public context; pending audio preview requires issuing reviewer auth", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher"),
    staff = await h.account("Church"),
    mod = await h.account("Mod");
  await h.staff(staff);
  await h.admin(mod);
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ rightsBasis: "churchReview", audio }),
  );
  assert.equal(
    (
      await h.mf.dispatchFetch(pub.uploadURL, {
        method: "PUT",
        headers: { "content-type": "audio/mp4" },
        body: audioBytes,
      })
    ).status,
    200,
  );
  await h.call(
    who,
    "POST",
    `/v1/publications/${pub.publicationID}/complete`,
    {},
  );
  const church = (
    await h.call(
      staff,
      "GET",
      "/v1/portal/churches/sample-church-west/publications",
    )
  ).items.find((p) => p.id === pub.publicationID);
  assert.equal(church.review.title, "Test sermon");
  assert.equal(church.review.audio.byteCount, audioBytes.length);
  assert.equal(church.review.contributorDisplayName, "Publisher");
  assert.equal(church.review.checklist.musicReviewed, true);
  const queue = (
    await h.call(mod, "GET", "/v1/moderation/queue?kind=publications")
  ).items;
  assert.equal(queue[0].review.rightsBasis, "churchReview");
  const preview = await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/publications/${pub.publicationID}/preview-url`,
    {},
  );
  const url = new URL(preview.url);
  assert.equal((await h.mf.dispatchFetch(preview.url)).status, 401);
  assert.equal(
    (await h.raw(who, "GET", url.pathname + url.search)).status,
    401,
  );
  const streamed = await h.raw(staff, "GET", url.pathname + url.search);
  assert.equal(streamed.status, 200);
  await streamed.arrayBuffer();
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        `/v1/moderation/publications/${pub.publicationID}/preview-url`,
        {},
      )
    ).status,
    403,
  );
  await h.call(who, "POST", "/v1/reports", {
    targetType: "audio",
    targetID: pub.audioAssetID,
    reason: "privacy",
  });
  assert.equal(
    (await h.call(mod, "GET", "/v1/moderation/queue?kind=reports")).items[0]
      .targetSummary,
    "Test sermon",
  );
  for (const path of ["/church", "/moderate", "/t/opaque.offer.token"]) {
    const response = await h.fetch(path);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  }
});
test("church staff claims unassigned sermons; cross-church correction is moderator-only and withdraws old audio scope", async (t) => {
  const h = await harness();
  t.after(h.close);
  const staff = await h.account("Staff"),
    mod = await h.account("Mod"),
    who = await h.account("Listener");
  await h.staff(staff);
  await h.admin(mod);
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ churchID: null }),
  );
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed metadata",
  });
  await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/sermons/${pub.sermonID}/claim`,
    { reason: "Verified church attribution" },
  );
  assert.equal(
    (await (await h.fetch(`/v1/sermons/${pub.sermonID}`)).json()).sermon
      .churchID,
    "sample-church-west",
  );
  assert.equal(
    (
      await h.raw(
        staff,
        "POST",
        "/v1/portal/churches/sample-church-west/sermons/sample-open-hands/claim",
        { reason: "Wrong church" },
      )
    ).status,
    409,
  );
  const link = await h.call(
    who,
    "POST",
    "/v1/sermons/sample-peace-in-the-storm/audio-url",
    {},
  );
  await h.call(
    mod,
    "POST",
    "/v1/moderation/sermons/sample-peace-in-the-storm/correct",
    {
      churchID: "sample-church-south",
      reason: "Verified attribution correction",
    },
  );
  assert.equal((await h.mf.dispatchFetch(link.url)).status, 410);
  assert.equal(
    (
      await h.raw(mod, "POST", "/v1/moderation/actions", {
        targetType: "sermon",
        targetID: "sample-peace-in-the-storm",
        action: "restore",
        reason: "Old grant is wrong church",
      })
    ).status,
    403,
  );
});
test("moderation rejects impossible transitions and can restore removed metadata without changing collections", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher");
  await h.admin(who);
  const pub = await h.call(who, "POST", "/v1/publications", metadata());
  assert.equal(
    (
      await h.raw(who, "POST", "/v1/moderation/actions", {
        targetType: "sermon",
        targetID: pub.sermonID,
        action: "restore",
        reason: "Never published",
      })
    ).status,
    409,
  );
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed",
  });
  await h.call(who, "POST", `/v1/sermons/${pub.sermonID}/keep`, {
    source: "discover",
  });
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "sermon",
    targetID: pub.sermonID,
    action: "remove",
    reason: "Pending review",
  });
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "sermon",
    targetID: pub.sermonID,
    action: "restore",
    reason: "Review resolved",
  });
  assert.equal(
    (await h.call(who, "GET", `/v1/publications/${pub.publicationID}`))
      .publication.state,
    "published",
  );
  assert.equal((await h.call(who, "GET", "/v1/cards")).items.length, 1);
});
