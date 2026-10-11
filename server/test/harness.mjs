import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { build } from "esbuild";
import { mkdir, readFile, readdir } from "node:fs/promises";
import { webcrypto, randomBytes } from "node:crypto";
import { apiClient } from "../scripts/client.mjs";
import { seedData } from "../scripts/seed-data.mjs";
await mkdir(".tmp", { recursive: true });
await build({
  entryPoints: ["test/entry.ts"],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  outfile: ".tmp/test-worker.mjs",
});
const key = await webcrypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
export const testBindings = {
  BRAND_NAME: "Test Community",
  BRAND_SCHEME: "testcommunity",
  PUBLIC_BASE_URL: "http://127.0.0.1:8787",
  TOKEN_KEY_ID: "test-key",
  TOKEN_SIGNING_JWK: JSON.stringify(
    await webcrypto.subtle.exportKey("jwk", key.privateKey),
  ),
  TOKEN_PUBLIC_KEYS: JSON.stringify([
    {
      kid: "test-key",
      alg: "ES256",
      publicKey: await webcrypto.subtle.exportKey("jwk", key.publicKey),
    },
  ]),
  CAPABILITY_SECRET: randomBytes(48).toString("base64url"),
  ADMIN_BOOTSTRAP_SECRET: randomBytes(48).toString("base64url"),
};
const schemas = await Promise.all(
  (await readdir("migrations"))
    .filter((name) => name.endsWith(".sql"))
    .sort()
    .map((name) => readFile("migrations/" + name, "utf8")),
);
export async function harness({ seed = true } = {}) {
  const mf = new Miniflare(
    convertV4MiniflareOptions({
      logRequests: false,
      modules: true,
      scriptPath: ".tmp/test-worker.mjs",
      compatibilityDate: "2026-09-01",
      bindings: testBindings,
      d1Databases: { DB: "community-test" },
      r2Buckets: ["AUDIO", "IMAGES"],
      serviceBindings: {
        ASSETS: async (req) => {
          const path = new URL(req.url).pathname;
          if (path === "/templates/share.html")
            return new Response(
              '<!doctype html><h1>{{title}}</h1><p>{{brandName}}</p><a href="{{appURL}}">Open</a><img src="{{imageURL}}">',
              { headers: { "content-type": "text/html" } },
            );
          if (path === "/templates/service-print.html")
            return new Response("<h1>{{churchName}}</h1><p>{{qrValue}}</p>", {
              headers: { "content-type": "text/html" },
            });
          return new Response("static-shell", {
            headers: { "content-type": "text/html" },
          });
        },
      },
    }),
  );
  const db = await mf.getD1Database("DB");
  for (const schema of schemas)
    for (const statement of schema
      .replace(/--[^\n]*/g, "")
      .split(/;\s*(?=PRAGMA|CREATE)/)) {
      if (statement.trim()) await db.prepare(statement).run();
    }
  if (seed) {
    const fixture = await seedData();
    await db.batch(
      fixture.statements.map((s) => db.prepare(s.query).bind(...s.args)),
    );
    const audio = await mf.getR2Bucket("AUDIO");
    for (const item of fixture.audio) await audio.put(item.key, item.bytes);
  }
  const client = apiClient((url, init) => mf.dispatchFetch(url, init));
  async function admin(who) {
    await db
      .prepare("INSERT INTO roles(account_id,role) VALUES(?,'admin')")
      .bind(who.id)
      .run();
  }
  async function staff(who, church = "sample-church-west") {
    await db
      .prepare(
        "INSERT INTO roles(account_id,role,church_id) VALUES(?,'churchStaff',?)",
      )
      .bind(who.id, church)
      .run();
  }
  return {
    mf,
    db,
    ...client,
    admin,
    staff,
    fetch: (path, options) =>
      mf.dispatchFetch(testBindings.PUBLIC_BASE_URL + path, options),
    close: () => mf.dispose(),
  };
}
export const metadata = (extra = {}) => ({
  title: "Test sermon",
  preacher: "Fictional Speaker",
  churchID: "sample-church-west",
  serviceDate: new Date().toISOString(),
  primaryPassage: "John 1:1",
  themes: ["Hope"],
  sermonType: "teaching",
  reviewed: true,
  checklist: {
    musicReviewed: true,
    prayerRequestsReviewed: true,
    childrenReviewed: true,
    privateTalkReviewed: true,
  },
  rightsBasis: "none",
  ...extra,
});
