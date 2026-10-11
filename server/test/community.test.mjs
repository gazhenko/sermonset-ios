import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { harness, metadata } from "./harness.mjs";
import { hash } from "../scripts/client.mjs";
test("seed is fictional and excludes sample notes/transcripts; discovery filters, pagination and public Atlas", async (t) => {
  const h = await harness();
  t.after(h.close);
  const feed = await (await h.fetch("/v1/discover?limit=3")).json();
  assert.equal(feed.items.length, 3);
  assert(feed.nextCursor);
  feed.items.forEach((s) => {
    assert.equal(s.fictional, true);
    assert(!("transcript" in s));
  });
  assert.equal(
    (await (await h.fetch("/v1/discover?city=Portland")).json()).items.length,
    1,
  );
  assert.equal(
    (await (await h.fetch("/v1/discover?theme=Transformation")).json()).items
      .length,
    1,
  );
  assert.equal(
    (await (await h.fetch("/v1/discover?q=shore")).json()).items.length,
    1,
  );
  assert.equal(
    (await (await h.fetch("/v1/discover?verified=true")).json()).items.length,
    8,
  );
  assert.equal((await (await h.fetch("/v1/churches")).json()).items.length, 3);
  const atlas = await (await h.fetch("/v1/atlas")).json();
  assert.equal(
    atlas.places.reduce((n, p) => n + p.count, 0),
    8,
  );
  assert(atlas.places.every((p) => !("latitude" in p) && !("longitude" in p)));
  assert.equal((await h.fetch("/v1/discover?cursor=bad")).status, 400);
});
test("private notes, transcripts, AI drafts, moments and precise location are rejected at every public boundary", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Listener");
  for (const key of [
    "notes",
    "personalNotes",
    "moments",
    "transcript",
    "draft",
    "latitude",
    "longitude",
    "playbackHistory",
    "originalAudio",
  ])
    assert.equal(
      (
        await h.raw(
          who,
          "POST",
          "/v1/publications",
          metadata({ [key]: "PRIVATE_CANARY" }),
        )
      ).status,
      400,
    );
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      summary: "Reviewed public summary",
      reflectionPrompt: "Reviewed public prompt",
    }),
  );
  await h.admin(who);
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed",
  });
  const card = await h.call(who, "POST", `/v1/sermons/${pub.sermonID}/keep`, {
    source: "discover",
  });
  assert.equal(
    (
      await h.raw(who, "POST", "/v1/offers", {
        kind: "gift",
        cardID: card.cardID,
        cardVersion: 1,
        notes: "PRIVATE_CANARY",
      })
    ).status,
    400,
  );
  assert.equal(
    (await h.raw(who, "PATCH", "/v1/me", { latitude: 1, longitude: 1 })).status,
    400,
  );
  for (const path of [
    "/v1/discover",
    "/v1/atlas",
    "/v1/cards",
    "/v1/library",
    "/v1/inbox",
    "/v1/publications",
    "/v1/moderation/queue?kind=publications",
  ]) {
    const response =
      path.startsWith("/v1/discover") || path === "/v1/atlas"
        ? await h.fetch(path)
        : await h.raw(who, "GET", path);
    const text = await response.text();
    assert(!text.includes("PRIVATE_CANARY"));
    for (const forbidden of [
      '"notes"',
      '"transcript"',
      '"moments"',
      '"latitude"',
      '"longitude"',
      '"storageKey"',
      '"public_key"',
      '"source_checksum"',
    ])
      assert(!text.includes(forbidden), `${path} leaked ${forbidden}`);
  }
});
test("Sunday pack is deterministic, excludes the library, freezes before opening, and opens once atomically", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Pack");
  await h.call(who, "POST", "/v1/sermons/sample-peace-in-the-storm/keep", {
    source: "discover",
  });
  const first = await h.call(who, "GET", "/v1/packs/current");
  assert.equal(first.sermonIDs.length, 5);
  assert(!first.sermonIDs.includes("sample-peace-in-the-storm"));
  assert.deepEqual(await h.call(who, "GET", "/v1/packs/current"), first);
  const responses = await Promise.all(
    Array.from({ length: 6 }, () =>
      h.raw(who, "POST", `/v1/packs/${first.week}/open`, {}),
    ),
  );
  assert(responses.every((r) => r.status === 200));
  assert.equal((await h.call(who, "GET", "/v1/cards")).items.length, 6);
  assert.equal((await h.call(who, "GET", "/v1/library")).items.length, 6);
  assert.equal((await h.call(who, "GET", "/v1/packs/current")).opened, true);
  assert.equal(
    (await h.raw(who, "POST", "/v1/packs/2000-W01/open", {})).status,
    410,
  );
});
test("undersized pool is labelled fallback without duplicate sermons or paid odds", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Small pack");
  for (const s of (await (await h.fetch("/v1/discover")).json()).items.slice(
    0,
    6,
  ))
    await h.call(who, "POST", `/v1/sermons/${s.id}/keep`, {
      source: "discover",
    });
  const pack = await h.call(who, "GET", "/v1/packs/current");
  assert.equal(pack.fallback, true);
  assert.equal(pack.sermonIDs.length, 2);
  assert.equal(new Set(pack.sermonIDs).size, 2);
  assert(!("odds" in pack));
});
test("journeys suppress small cohorts, require every participant opt-in and honor hide-past", async (t) => {
  const h = await harness();
  t.after(h.close);
  const accounts = await Promise.all([
    h.account("A"),
    h.account("B"),
    h.account("C"),
  ]);
  const cards = [];
  for (const who of accounts) {
    await h.call(who, "PATCH", "/v1/me", {
      journeyOptIn: true,
      journeyCity: "Portland",
    });
    cards.push(
      (
        await h.call(
          who,
          "POST",
          "/v1/sermons/sample-peace-in-the-storm/keep",
          { source: "discover" },
        )
      ).cardID,
    );
    if (cards.length < 3)
      assert.equal(
        (await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json())
          .suppressed,
        true,
      );
  }
  let trace = await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json();
  assert.equal(trace.suppressed, false);
  assert.deepEqual(Object.keys(trace.stops[0]), ["city", "week"]);
  await h.call(accounts[2], "PATCH", "/v1/me", { journeyOptIn: false });
  assert.equal(
    (await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json()).suppressed,
    true,
  );
  await h.call(accounts[2], "PATCH", "/v1/me", { journeyOptIn: true });
  await h.call(accounts[0], "PATCH", "/v1/me", { hidePastJourneys: true });
  assert.equal(
    (await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json()).suppressed,
    true,
  );
});
test("unconsenting recipient hides the entire card journey; cron cohort cache cannot disclose stale consent", async (t) => {
  const h = await harness();
  t.after(h.close);
  const a = await h.account("A"),
    b = await h.account("B");
  await h.call(a, "PATCH", "/v1/me", {
    journeyOptIn: true,
    journeyCity: "Portland",
  });
  const cards = [];
  for (const s of (await (await h.fetch("/v1/discover")).json()).items.slice(
    0,
    3,
  ))
    cards.push(
      (
        await h.call(a, "POST", `/v1/sermons/${s.id}/keep`, {
          source: "discover",
        })
      ).cardID,
    );
  await h.fetch("/__fixture/cron");
  assert.equal(
    (await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json()).suppressed,
    false,
  );
  const offer = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: cards[0],
    cardVersion: 1,
    recipientID: b.id,
  });
  await h.call(b, "POST", `/v1/offers/${offer.offerID}/accept`, {});
  assert.equal(
    (await (await h.fetch(`/v1/cards/${cards[0]}/journey`)).json()).suppressed,
    true,
  );
});
test("cron expires offers exactly once, builds weekly pools, cleans nonce/session state", async (t) => {
  const h = await harness();
  t.after(h.close);
  const a = await h.account("A"),
    b = await h.account("B");
  const card = await h.call(a, "POST", "/v1/sermons/sample-open-hands/keep", {
    source: "discover",
  });
  const offer = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.cardID,
    cardVersion: 1,
    recipientID: b.id,
  });
  await h.db
    .prepare("UPDATE offers SET expires_at='2000-01-01T00:00:00Z' WHERE id=?")
    .bind(offer.offerID)
    .run();
  await h.fetch("/__fixture/cron?cron=0%200%20*%20*%20SUN");
  await h.fetch("/__fixture/cron");
  assert.equal(
    (
      await h.db
        .prepare("SELECT state FROM offers WHERE id=?")
        .bind(offer.offerID)
        .first()
    ).state,
    "expired",
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT COUNT(*) AS n FROM inbox WHERE type='offerExpired'")
        .first()
    ).n,
    2,
  );
  for (const who of [a, b])
    assert.equal(
      (await h.call(who, "GET", "/v1/inbox")).items.filter(
        (e) => e.type === "offerExpired" && e.resourceID === offer.offerID,
      ).length,
      1,
    );
  assert.equal(
    (await h.db.prepare("SELECT COUNT(*) AS n FROM pack_pools").first()).n,
    1,
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT version FROM cards WHERE id=?")
        .bind(card.cardID)
        .first()
    ).version,
    1,
  );
});
test("streaming SHA-256 matches independent vectors across multi-block chunk boundaries", async (t) => {
  const h = await harness({ seed: false });
  t.after(h.close);
  for (const length of [0, 1, 55, 56, 63, 64, 65, 127, 1000000]) {
    const bytes = Buffer.alloc(length, 0x61);
    const response = await h.fetch("/__fixture/hash", {
      method: "POST",
      body: bytes,
    });
    assert.equal((await response.json()).hash, hash(bytes));
  }
});
test("full-length search is literal, including percent and underscore characters", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Search");
  await h.admin(who);
  const title =
    "Fictional sermon " + randomUUID() + " — 100% hope_under_pressure";
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ title }),
  );
  await h.call(who, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed",
  });
  const response = await h.fetch("/v1/discover?q=" + encodeURIComponent(title));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).items[0].id, pub.sermonID);
});
test("contribution credit defaults private and requires both account opt-in and church policy", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Named publisher"),
    viewer = await h.account("Viewer"),
    staff = await h.account("Staff");
  await h.admin(staff);
  await h.staff(staff);
  const pub = await h.call(who, "POST", "/v1/publications", metadata());
  await h.call(staff, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed",
  });
  await h.call(staff, "PATCH", "/v1/portal/churches/sample-church-west", {
    creditPolicy: "named",
  });
  const path = `/v1/sermons/${pub.sermonID}/contributors`;
  assert.equal((await (await h.fetch(path)).json()).items[0].displayName, null);
  await h.call(who, "PATCH", "/v1/me", { creditOptIn: true });
  assert.equal(
    (await (await h.fetch(path)).json()).items[0].displayName,
    "Named publisher",
  );
  await h.call(viewer, "POST", "/v1/blocks", { accountID: who.id });
  assert.equal((await h.call(viewer, "GET", path)).items[0].displayName, null);
  await h.call(staff, "PATCH", "/v1/portal/churches/sample-church-west", {
    creditPolicy: "anonymous",
  });
  assert.equal((await (await h.fetch(path)).json()).items[0].displayName, null);
});
test("pack composition favors distinct churches and themes with deterministic tie-breaking", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Diverse pack");
  const pack = await h.call(who, "GET", "/v1/packs/current");
  const chosen = (
    await h.db.prepare("SELECT id,church_id FROM sermons").all()
  ).results.filter((s) => pack.sermonIDs.includes(s.id));
  assert.equal(new Set(chosen.map((s) => s.church_id)).size, 3);
  assert.deepEqual(
    (await h.call(who, "GET", "/v1/packs/current")).sermonIDs,
    pack.sermonIDs,
  );
});
