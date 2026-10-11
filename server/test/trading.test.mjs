import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { harness } from "./harness.mjs";
async function setup(t) {
  const h = await harness();
  t.after(h.close);
  const a = await h.account("Sender"),
    b = await h.account("Recipient");
  const minted = await h.call(
    a,
    "POST",
    "/v1/sermons/sample-peace-in-the-storm/keep",
    { source: "discover" },
  );
  const card = (await h.call(a, "GET", "/v1/cards")).items.find(
    (c) => c.id === minted.cardID,
  );
  const offer = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: card.version,
    recipientID: b.id,
  });
  return { h, a, b, card, offer };
}
test("gift transfer preserves both libraries; retries mint and transfer exactly once", async (t) => {
  const { h, a, b, card, offer } = await setup(t);
  const key = randomUUID();
  const result = await h.call(
    b,
    "POST",
    `/v1/offers/${offer.offerID}/accept`,
    {},
    { key },
  );
  assert.deepEqual(
    await h.call(b, "POST", `/v1/offers/${offer.offerID}/accept`, {}, { key }),
    result,
  );
  assert.equal((await h.call(a, "GET", "/v1/cards")).items.length, 0);
  const received = (await h.call(b, "GET", "/v1/cards")).items;
  assert.equal(received.length, 1);
  assert.equal(received[0].version, 2);
  assert.equal(received[0].id, card.id);
  assert.equal((await h.call(a, "GET", "/v1/library")).items.length, 1);
  assert.equal((await h.call(b, "GET", "/v1/library")).items.length, 1);
  assert.equal(
    (
      await h.call(a, "POST", "/v1/sermons/sample-peace-in-the-storm/keep", {
        source: "discover",
      })
    ).cardID,
    card.id,
  );
  assert.equal((await h.call(a, "GET", "/v1/cards")).items.length, 0);
  assert.equal(
    (
      await h.db
        .prepare("SELECT COUNT(*) AS n FROM journey_events WHERE card_id=?")
        .bind(card.id)
        .first()
    ).n,
    2,
  );
});
test("concurrent same-key acceptance returns one result and one transfer", async (t) => {
  const { h, a, b, card, offer } = await setup(t);
  const key = randomUUID();
  const replies = await Promise.all(
    Array.from({ length: 8 }, () =>
      h.raw(b, "POST", `/v1/offers/${offer.offerID}/accept`, {}, { key }),
    ),
  );
  assert.deepEqual(
    replies.map((r) => r.status),
    Array(8).fill(200),
  );
  const values = await Promise.all(replies.map((r) => r.json()));
  values.forEach((v) => assert.deepEqual(v, values[0]));
  assert.equal(
    (
      await h.db
        .prepare("SELECT version FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).version,
    2,
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT COUNT(*) AS n FROM inbox WHERE type='offerAccepted'")
        .first()
    ).n,
    1,
  );
  assert.deepEqual(
    (await h.call(a, "GET", "/v1/inbox")).items.map((e) => e.type),
    ["offerAccepted"],
  );
  assert.deepEqual(
    (await h.call(b, "GET", "/v1/inbox")).items.map((e) => e.type),
    ["offerReceived"],
  );
});
test("different-key duplicate acceptance and competing offers cannot consume a version twice", async (t) => {
  const { h, a, b, card, offer } = await setup(t);
  const third = await h.account("Third");
  const other = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 1,
    recipientID: third.id,
  });
  const replies = await Promise.all([
    h.raw(b, "POST", `/v1/offers/${offer.offerID}/accept`, {}),
    h.raw(third, "POST", `/v1/offers/${other.offerID}/accept`, {}),
  ]);
  assert.deepEqual(replies.map((r) => r.status).sort(), [200, 409]);
  assert.equal(
    (
      await h.db
        .prepare("SELECT version FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).version,
    2,
  );
  const winner = replies[0].status === 200 ? b : third,
    id = replies[0].status === 200 ? offer.offerID : other.offerID;
  assert.equal(
    (await h.raw(winner, "POST", `/v1/offers/${id}/accept`, {})).status,
    409,
  );
});
test("swap proposal awaits sender; confirmation transfers both cards atomically", async (t) => {
  const { h, a, b, card } = await setup(t);
  const kept = await h.call(
    b,
    "POST",
    "/v1/sermons/sample-when-faith-gets-loud/keep",
    { source: "discover" },
  );
  const swap = await h.call(a, "POST", "/v1/offers", {
    kind: "swap",
    cardID: card.id,
    cardVersion: 1,
    recipientID: b.id,
  });
  assert.equal(
    (await h.raw(b, "POST", `/v1/offers/${swap.offerID}/accept`, {})).status,
    409,
  );
  await h.call(b, "POST", `/v1/offers/${swap.offerID}/propose`, {
    cardID: kept.cardID,
    cardVersion: 1,
  });
  assert.equal(
    (
      await h.db
        .prepare("SELECT owner_id FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).owner_id,
    a.id,
  );
  assert.equal(
    (await h.raw(b, "POST", `/v1/offers/${swap.offerID}/confirm`, {})).status,
    403,
  );
  await h.call(a, "POST", `/v1/offers/${swap.offerID}/confirm`, {});
  assert.equal(
    (
      await h.db
        .prepare("SELECT owner_id FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).owner_id,
    b.id,
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT owner_id FROM cards WHERE id=?")
        .bind(kept.cardID)
        .first()
    ).owner_id,
    a.id,
  );
  for (const who of [a, b])
    assert.equal((await h.call(who, "GET", "/v1/library")).items.length, 2);
});
test("a stale swap proposal rolls back both sides and retry receipt", async (t) => {
  const { h, a, b, card } = await setup(t);
  const third = await h.account("Third");
  const kept = await h.call(
    b,
    "POST",
    "/v1/sermons/sample-when-faith-gets-loud/keep",
    { source: "discover" },
  );
  const swap = await h.call(a, "POST", "/v1/offers", {
    kind: "swap",
    cardID: card.id,
    cardVersion: 1,
    recipientID: b.id,
  });
  await h.call(b, "POST", `/v1/offers/${swap.offerID}/propose`, {
    cardID: kept.cardID,
    cardVersion: 1,
  });
  const gift = await h.call(b, "POST", "/v1/offers", {
    kind: "gift",
    cardID: kept.cardID,
    cardVersion: 1,
    recipientID: third.id,
  });
  await h.call(third, "POST", `/v1/offers/${gift.offerID}/accept`, {});
  const key = randomUUID();
  assert.equal(
    (await h.raw(a, "POST", `/v1/offers/${swap.offerID}/confirm`, {}, { key }))
      .status,
    409,
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT owner_id,version FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).owner_id,
    a.id,
  );
  assert.equal(
    await h.db
      .prepare("SELECT 1 FROM commands WHERE account_id=? AND key=?")
      .bind(a.id, key)
      .first(),
    null,
  );
  assert.equal(
    await h.db
      .prepare(
        "SELECT 1 FROM inbox WHERE resource_id=? AND type='offerAccepted'",
      )
      .bind(swap.offerID)
      .first(),
    null,
  );
});
test("expiry, cancellation and decline change no ownership or library state", async (t) => {
  const { h, a, b, card, offer } = await setup(t);
  await h.call(a, "POST", `/v1/offers/${offer.offerID}/cancel`, {});
  assert.equal(
    (await h.raw(b, "POST", `/v1/offers/${offer.offerID}/accept`, {})).status,
    409,
  );
  const declined = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 1,
    recipientID: b.id,
  });
  await h.call(b, "POST", `/v1/offers/${declined.offerID}/decline`, {});
  const expired = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 1,
    recipientID: b.id,
  });
  await h.db
    .prepare("UPDATE offers SET expires_at='2000-01-01T00:00:00Z' WHERE id=?")
    .bind(expired.offerID)
    .run();
  assert.equal(
    (await h.raw(b, "POST", `/v1/offers/${expired.offerID}/accept`, {})).status,
    410,
  );
  assert.equal(
    (
      await h.db
        .prepare("SELECT owner_id,version FROM cards WHERE id=?")
        .bind(card.id)
        .first()
    ).version,
    1,
  );
  assert.equal((await h.call(b, "GET", "/v1/library")).items.length, 0);
});
test("bearer offers are recipient-bound; blocking prevents preview, token acceptance and name disclosure", async (t) => {
  const { h, a, b, card } = await setup(t);
  const third = await h.account("Third");
  const open = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 1,
    message: "A public gift message",
  });
  assert.equal(
    (await h.raw(b, "GET", `/v1/offers/${open.offerID}`)).status,
    401,
  );
  assert.equal(
    (await h.call(b, "GET", `/v1/offers/${open.offerID}?token=${open.token}`))
      .senderDisplayName,
    "Sender",
  );
  await h.call(b, "POST", "/v1/blocks", { accountID: a.id });
  assert.equal(
    (await h.raw(b, "GET", `/v1/offers/${open.offerID}?token=${open.token}`))
      .status,
    403,
  );
  assert.equal(
    (
      await h.raw(b, "POST", `/v1/offers/${open.offerID}/accept`, {
        token: open.token,
      })
    ).status,
    403,
  );
  const bound = await h.call(a, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 1,
    recipientID: third.id,
  });
  assert.equal(
    (
      await h.raw(b, "POST", `/v1/offers/${bound.offerID}/accept`, {
        token: bound.token,
      })
    ).status,
    403,
  );
});
test("idempotency keys reject changed request bytes; serials stay unique under concurrent minting", async (t) => {
  const { h, a } = await setup(t);
  const key = randomUUID();
  await h.call(a, "PATCH", "/v1/me", { displayName: "One" }, { key });
  assert.equal(
    (await h.raw(a, "PATCH", "/v1/me", { displayName: "Two" }, { key })).status,
    409,
  );
  const accounts = await Promise.all(
    Array.from({ length: 5 }, (_, i) => h.account("Mint " + i)),
  );
  await Promise.all(
    accounts.map((who) =>
      h.call(who, "POST", "/v1/sermons/sample-open-hands/keep", {
        source: "discover",
      }),
    ),
  );
  const cards = (
    await h.db
      .prepare(
        "SELECT serial_number FROM cards c JOIN editions e ON e.id=c.edition_id WHERE e.sermon_id='sample-open-hands'",
      )
      .all()
  ).results;
  assert.equal(new Set(cards.map((c) => c.serial_number)).size, 5);
});
test("card ledger survives onward trades, hides participant identities, and is participant-only", async (t) => {
  const { h, a, b, card, offer } = await setup(t);
  const third = await h.account("Third");
  await h.call(b, "POST", `/v1/offers/${offer.offerID}/accept`, {});
  const gift = await h.call(b, "POST", "/v1/offers", {
    kind: "gift",
    cardID: card.id,
    cardVersion: 2,
    recipientID: third.id,
  });
  await h.call(third, "POST", `/v1/offers/${gift.offerID}/accept`, {});
  const history = await h.call(a, "GET", `/v1/cards/${card.id}/history`);
  assert.deepEqual(
    history.items.map((e) => e.version),
    [1, 2, 3],
  );
  assert.deepEqual(Object.keys(history.items[2]), [
    "version",
    "kind",
    "occurredAt",
  ]);
  const stranger = await h.account("Stranger");
  assert.equal(
    (await h.raw(stranger, "GET", `/v1/cards/${card.id}/history`)).status,
    403,
  );
});
