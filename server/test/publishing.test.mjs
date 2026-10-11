import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { harness, metadata } from "./harness.mjs";
import { hash } from "../scripts/client.mjs";
const bytes = await readFile(
  "../Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/peace-in-the-storm.m4a",
);
export const audio = () => ({
  byteCount: bytes.length,
  duration: 101.599667,
  checksumSHA256: hash(bytes),
  sourceChecksumSHA256: "a".repeat(64),
  contentType: "audio/mp4",
  trimStart: 1,
  trimEnd: 102.599667,
});
async function upload(h, url, data = bytes) {
  return h.mf.dispatchFetch(url, {
    method: "PUT",
    headers: { "content-type": "audio/mp4" },
    body: data,
  });
}
test("review and rights gates precede public audio; metadata-only sermons may publish", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher"),
    mod = await h.account("Moderator");
  await h.admin(mod);
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({ reviewed: false }),
      )
    ).status,
    400,
  );
  assert.equal(
    (await h.raw(who, "POST", "/v1/publications", metadata({ audio: audio() })))
      .status,
    403,
  );
  const pub = await h.call(who, "POST", "/v1/publications", metadata());
  assert.equal(
    (await h.raw(who, "POST", `/v1/sermons/${pub.sermonID}/audio-url`, {}))
      .status,
    410,
  );
  await h.call(mod, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pub.publicationID,
    action: "approve",
    reason: "Reviewed metadata only",
  });
  const sermon = (await (await h.fetch(`/v1/sermons/${pub.sermonID}`)).json())
    .sermon;
  assert.equal(sermon.audioAvailable, false);
  assert(!sermon.trustLabels.includes("Audio authorized"));
});
test("valid AAC upload remains private until church approval; removal revokes issued URLs and preserves cards/history", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher"),
    staff = await h.account("Church");
  await h.staff(staff);
  const pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ rightsBasis: "churchReview", audio: audio() }),
  );
  assert.deepEqual((await h.call(who, "GET", "/v1/inbox")).items, []);
  assert.equal((await upload(h, pub.uploadURL)).status, 200);
  await h.call(
    who,
    "POST",
    `/v1/publications/${pub.publicationID}/complete`,
    {},
  );
  assert.deepEqual((await h.call(who, "GET", "/v1/inbox")).items, []);
  assert.equal(
    (await h.raw(who, "POST", `/v1/sermons/${pub.sermonID}/audio-url`, {}))
      .status,
    410,
  );
  await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/publications/${pub.publicationID}/decision`,
    { decision: "approve", reason: "Verified scoped church permission" },
  );
  const issued = await h.call(
    who,
    "POST",
    `/v1/sermons/${pub.sermonID}/audio-url`,
    {},
  );
  let streamed = await h.mf.dispatchFetch(issued.url, {
    headers: { range: "bytes=0-31" },
  });
  assert.equal(streamed.status, 206);
  assert.equal((await streamed.arrayBuffer()).byteLength, 32);
  const card = await h.call(who, "POST", `/v1/sermons/${pub.sermonID}/keep`, {
    source: "discover",
  });
  await h.call(
    staff,
    "POST",
    "/v1/portal/churches/sample-church-west/removals",
    { sermonID: pub.sermonID, reason: "Rightsholder withdrawal" },
  );
  assert.deepEqual((await h.call(staff, "GET", "/v1/inbox")).items, []);
  assert.equal((await h.mf.dispatchFetch(issued.url)).status, 410);
  assert.equal(
    (await h.raw(who, "POST", `/v1/sermons/${pub.sermonID}/audio-url`, {}))
      .status,
    410,
  );
  assert.equal(
    (await h.call(who, "GET", "/v1/cards")).items[0].id,
    card.cardID,
  );
  assert.equal(
    (await h.call(who, "GET", "/v1/library")).items[0].sermonID,
    pub.sermonID,
  );
});
test("upload validation rejects corruption, false codec, false duration, size and untrimmed originals", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher");
  const bad = Buffer.from(bytes);
  bad[0] ^= 1;
  let pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({ rightsBasis: "churchReview", audio: audio() }),
  );
  assert.equal((await upload(h, pub.uploadURL, bad)).status, 422);
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        `/v1/publications/${pub.publicationID}/complete`,
        {},
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          rightsBasis: "churchReview",
          audio: { ...audio(), byteCount: 200000001 },
        }),
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          rightsBasis: "churchReview",
          audio: { ...audio(), trimEnd: 200 },
        }),
      )
    ).status,
    400,
  );
  assert.equal(
    (
      await h.raw(
        who,
        "POST",
        "/v1/publications",
        metadata({
          rightsBasis: "churchReview",
          audio: { ...audio(), sourceChecksumSHA256: hash(bytes) },
        }),
      )
    ).status,
    400,
  );
  pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      rightsBasis: "churchReview",
      audio: { ...audio(), duration: 5, trimEnd: 6 },
    }),
  );
  assert.equal((await upload(h, pub.uploadURL)).status, 422);
});
test("canonical matching is concurrent-safe and reviewed official master supersedes without retiming history", async (t) => {
  const h = await harness();
  t.after(h.close);
  const a = await h.account("One"),
    b = await h.account("Two"),
    staff = await h.account("Staff");
  await h.staff(staff);
  const pubs = await Promise.all([
    h.call(a, "POST", "/v1/publications", metadata()),
    h.call(b, "POST", "/v1/publications", metadata()),
  ]);
  assert.equal(pubs[0].sermonID, pubs[1].sermonID);
  await h.admin(staff);
  await h.call(staff, "POST", "/v1/moderation/actions", {
    targetType: "publication",
    targetID: pubs[0].publicationID,
    action: "approve",
    reason: "Reviewed",
  });
  await h.call(a, "POST", `/v1/sermons/${pubs[0].sermonID}/keep`, {
    source: "discover",
  });
  const official = await h.call(
    staff,
    "POST",
    "/v1/portal/churches/sample-church-west/official-audio",
    metadata({ rightsBasis: "official", audio: audio() }),
  );
  assert.equal(official.sermonID, pubs[0].sermonID);
  assert.equal((await upload(h, official.uploadURL)).status, 200);
  await h.call(
    staff,
    "POST",
    `/v1/publications/${official.publicationID}/complete`,
    {},
  );
  assert.deepEqual((await h.call(staff, "GET", "/v1/inbox")).items, []);
  const issued = await h.call(
    a,
    "POST",
    `/v1/sermons/${pubs[0].sermonID}/audio-url`,
    {},
  );
  assert.equal(issued.audioAssetID, official.audioAssetID);
  assert.equal(issued.alignmentWarning, "Your moments may shift.");
  assert.equal((await h.call(a, "GET", "/v1/cards")).items.length, 1);
});
test("correct checksum cannot disguise a non-AAC codec; uploaded audio remains immutable on completion retries", async (t) => {
  const h = await harness();
  t.after(h.close);
  const who = await h.account("Publisher"),
    staff = await h.account("Staff");
  await h.staff(staff);
  const altered = Buffer.from(bytes);
  const offset = altered.indexOf(Buffer.from("mp4a"));
  assert(offset > 0);
  altered.write("alac", offset);
  let pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      rightsBasis: "churchReview",
      audio: { ...audio(), checksumSHA256: hash(altered) },
    }),
  );
  assert.equal((await upload(h, pub.uploadURL, altered)).status, 422);
  pub = await h.call(
    who,
    "POST",
    "/v1/publications",
    metadata({
      title: "Valid immutable asset",
      primaryPassage: "John 2:1",
      rightsBasis: "churchReview",
      audio: audio(),
    }),
  );
  assert.equal((await upload(h, pub.uploadURL)).status, 200);
  await h.call(
    who,
    "POST",
    `/v1/publications/${pub.publicationID}/complete`,
    {},
  );
  await h.call(
    staff,
    "POST",
    `/v1/portal/churches/sample-church-west/publications/${pub.publicationID}/decision`,
    { decision: "approve", reason: "Verified grant" },
  );
  assert.equal((await upload(h, pub.uploadURL)).status, 200);
  assert.equal(
    hash(
      Buffer.from(
        await (
          await (
            await h.mf.getR2Bucket("AUDIO")
          ).get(`private/audio/${pub.audioAssetID}`)
        ).arrayBuffer(),
      ),
    ),
    hash(bytes),
  );
});
