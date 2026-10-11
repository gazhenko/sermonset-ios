import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { apiClient, hash } from "./client.mjs";
const base = process.env.COMMUNITY_LOCAL_URL ?? "http://127.0.0.1:8787";
const url = new URL(base);
if (
  url.protocol !== "http:" ||
  !["127.0.0.1", "localhost"].includes(url.hostname)
)
  throw Error("Smoke only permits the local Worker.");
const api = apiClient(fetch, base);
const a = await api.account("Fictional smoke publisher"),
  b = await api.account("Fictional smoke recipient");
const role = spawnSync(
  process.execPath,
  [
    "scripts/dev.mjs",
    "d1",
    "execute",
    "DB",
    "--local",
    "--persist-to",
    ".wrangler/state",
    "--command",
    `INSERT INTO roles(account_id,role) VALUES('${a.id}','admin')`,
  ],
  { encoding: "utf8" },
);
if (role.status !== 0)
  throw Error("Could not create the isolated local moderator fixture.");
const bytes = await readFile(
  "../Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/peace-in-the-storm.m4a",
);
const runID = randomUUID();
const title = "Fictional smoke sermon " + runID;
const pub = await api.call(a, "POST", "/v1/publications", {
  title,
  preacher: "Fictional speaker",
  churchID: "sample-church-west",
  serviceDate: new Date().toISOString(),
  primaryPassage: "Psalm 23 (fictional run " + runID + ")",
  themes: ["Hope"],
  sermonType: "teaching",
  city: "Portland",
  region: "OR",
  country: "US",
  summary: "Fictional smoke metadata, explicitly reviewed.",
  reviewed: true,
  checklist: {
    musicReviewed: true,
    prayerRequestsReviewed: true,
    childrenReviewed: true,
    privateTalkReviewed: true,
  },
  rightsBasis: "churchReview",
  audio: {
    byteCount: bytes.length,
    duration: 101.599667,
    checksumSHA256: hash(bytes),
    sourceChecksumSHA256: "a".repeat(64),
    contentType: "audio/mp4",
    trimStart: 1,
    trimEnd: 102.599667,
  },
});
let response = await fetch(pub.uploadURL, {
  method: "PUT",
  headers: { "content-type": "audio/mp4" },
  body: bytes,
});
assert.equal(response.status, 200, await response.text());
await api.call(a, "POST", `/v1/publications/${pub.publicationID}/complete`, {});
assert.equal(
  (await api.raw(b, "POST", `/v1/sermons/${pub.sermonID}/audio-url`, {}))
    .status,
  410,
);
await api.call(a, "POST", "/v1/moderation/actions", {
  targetType: "publication",
  targetID: pub.publicationID,
  action: "approve",
  reason: "Fictional smoke rights grant checked",
});
const discovered = await (
  await fetch(base + "/v1/discover?q=" + encodeURIComponent(title))
).json();
assert(discovered.items.some((s) => s.id === pub.sermonID));
const kept = await api.call(a, "POST", `/v1/sermons/${pub.sermonID}/keep`, {
  source: "discover",
});
const offer = await api.call(a, "POST", "/v1/offers", {
  kind: "gift",
  cardID: kept.cardID,
  cardVersion: 1,
  recipientID: b.id,
});
const key = randomUUID();
await api.call(b, "POST", `/v1/offers/${offer.offerID}/accept`, {}, { key });
await api.call(b, "POST", `/v1/offers/${offer.offerID}/accept`, {}, { key });
const pack = await api.call(b, "GET", "/v1/packs/current");
await api.call(b, "POST", `/v1/packs/${pack.week}/open`, {});
const playback = await api.call(
  b,
  "POST",
  `/v1/sermons/${pub.sermonID}/audio-url`,
  {},
);
response = await fetch(playback.url, { headers: { range: "bytes=0-31" } });
assert.equal(response.status, 206);
assert.equal((await response.arrayBuffer()).byteLength, 32);
const report = await api.call(b, "POST", "/v1/reports", {
  targetType: "sermon",
  targetID: pub.sermonID,
  reason: "privacy",
  timestamp: 30,
  details: "Fictional smoke report",
});
assert(
  (await api.call(a, "GET", "/v1/moderation/queue?kind=reports")).items.some(
    (r) => r.id === report.reportID,
  ),
);
await api.call(a, "POST", "/v1/moderation/actions", {
  targetType: "sermon",
  targetID: pub.sermonID,
  action: "remove",
  reason: "Fictional smoke takedown",
});
assert.equal((await fetch(playback.url)).status, 410);
for (const who of [a, b])
  assert(
    (await api.call(who, "GET", "/v1/library")).items.some(
      (s) => s.sermonID === pub.sermonID,
    ),
  );
assert(
  (await api.call(b, "GET", "/v1/cards")).items.some(
    (c) => c.id === kept.cardID,
  ),
);
for (const path of ["/", "/church", "/moderate", "/t/" + offer.token]) {
  response = await fetch(base + path);
  assert.equal(response.status, 200, path);
  await response.text();
}
console.log(
  "PASS: two signed accounts → validated upload → rights approval → discovery → keep → gift/retry → Sunday Pack → ranged audio → report → takedown; both histories and recipient card preserved; static pages served.",
);
