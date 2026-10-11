# Community Worker

The API, state machines, signed-request bytes, token verification, and web templates are specified
in [API.md](../docs/api/API.md). The implementation uses a plain TypeScript fetch router, D1,
private R2, static assets from `../web`, and cron. Nothing here uploads private iPhone data implicitly.

## Local use

Run from `server/` with Node 22.23.1 or a compatible version. This session installed nothing and used
the existing read-only cached toolchain via an ignored `node_modules` symlink:

```sh
ln -s /Users/jemmygazhenko/Documents/GitHub/ink-drift-tokyo/Relay/node_modules node_modules
node scripts/local-keys.mjs
npm run migrate
npm run seed
npm run dev
```

If the symlink already exists, omit that command. Cached versions: Wrangler 4.147.0,
Miniflare 5.20261001.0-alpha, esbuild 0.28.1. package-lock.json records that exact existing dependency
graph. An alternate machine must supply this toolchain; it is not downloaded automatically.

The key script creates disposable local-only fixture secrets in `.dev.vars` (0600), preserving any
existing file. Never promote those keys to production. The local wrapper derives an ignored config
with `http://127.0.0.1:8787`, absolute resource paths, and D1/R2 persistence in `.wrangler/state`.
It hides the update-check banner, disables metrics and local observability/explorer, and keeps logs
and the development registry under `.tmp`. It refuses deployment and `--remote`. Production brand
and domain values live only in `wrangler.toml`. An absent `../web` is supported locally using API
and minimal server fallback pages; add Claude's files and restart to enable static pages.

The seed copies eight fictional samples' public metadata and existing M4A files from the Swift
package, verifies their checksums, and creates three explicitly fictional church networks. It keeps
all eight city-level sermon venues. These network affiliations are demonstration fixtures rather
than assertions about real churches. It never imports sample transcripts, notes, moments, or AI
outputs. Seed grants are fictional fixtures and must never be loaded into production.

In another terminal:

```sh
npm run check
npm test
npm run smoke
```

`check` bundles TypeScript with esbuild and checks the disabled observability setting; it is not a
full TypeScript typecheck. Tests run actual Worker code against disposable Miniflare D1/R2 instances,
apply every migration, and use a test-only entry point for cron/hash fixtures. Production exclusively
loads `src/index.ts`; the fixture routes are absent from the production bundle. Smoke refuses remote
hosts, creates two disposable signed accounts, assigns a local D1 admin fixture, uploads and approves
sample audio, discovers and keeps it, gifts and retries acceptance, opens a pack, plays a byte range,
reports it, and removes audio while checking both histories and the recipient's card. Repeated runs
use unique title/passage metadata to avoid matching an earlier run's canonical sermon. Local fixtures
remain in ignored persistence for inspection.

Wrangler does not automatically fire cron during development. Invoke its local scheduled hook:

```sh
curl 'http://127.0.0.1:8787/cdn-cgi/local/scheduled?cron=0%200%20*%20*%20SUN'
curl 'http://127.0.0.1:8787/cdn-cgi/local/scheduled?cron=0%20*%20*%20*%20*'
```

The first builds a weekly pool; both expire offers, recompute journey cohorts, clean ephemeral
identity/session state, and retry account-deletion media cleanup. API pack allocation also ensures
this week's pool exists. Packs freeze their first selection and opening is atomic and repeatable.

## Deploy later, after owner approval

These are instructions only. No remote resources, deployment, DNS, or production keys were touched.
Use an authorized operator's Cloudflare account with access to the intended zone. From `server/`,
with the already-provisioned pinned toolchain:

```sh
./node_modules/.bin/wrangler d1 create sower-db
./node_modules/.bin/wrangler r2 bucket create sower-audio
./node_modules/.bin/wrangler r2 bucket create sower-images
```

Replace the zero `database_id` in wrangler.toml with the returned D1 ID. Verify the domain, zone,
Worker name and all three brand vars there. Keep both R2 buckets private; do not enable r2.dev or
public bucket domains. Ensure the approved static files/templates are present in `../web`.

Prepare a fresh production P-256 signing key and a published-key array in an operator-controlled
secret manager, separate from local fixtures. The private JWK must have `d` and support sign; the
published array is `[{kid:"community-p256-v1",alg:"ES256",publicKey:{kty:"EC",crv:"P-256",x,y}}]`.
Set TOKEN_KEY_ID to the active key's kid. Keep old public keys published until all their service and
offer tokens expire. Provision independent cryptographically random ≥32-character bootstrap and
capability secrets. Enter these via Wrangler's interactive prompts, never shell literals, URLs, or
committed files:

```sh
./node_modules/.bin/wrangler secret put TOKEN_SIGNING_JWK
./node_modules/.bin/wrangler secret put TOKEN_PUBLIC_KEYS
./node_modules/.bin/wrangler secret put CAPABILITY_SECRET
./node_modules/.bin/wrangler secret put ADMIN_BOOTSTRAP_SECRET
./node_modules/.bin/wrangler d1 migrations apply DB --remote
./node_modules/.bin/wrangler deploy
```

The deploy command registers the `sower.gazhenko.dev` custom domain configured in wrangler.toml;
the zone must already be available to that account. There is no workers.dev public fallback. Confirm
D1/R2 bindings, weekly/hourly cron schedules, disabled observability, and HTTPS secure session cookies.
Do not run seed or smoke remotely. Bootstrap an existing app account as admin through the protected
web session endpoint. After the initial operator can sign requests/link a browser, delete the
bootstrap secret to close that route:

```sh
./node_modules/.bin/wrangler secret delete ADMIN_BOOTSTRAP_SECRET
```

Configure a private R2 lifecycle rule for `private/staging/` to delete abandoned partial staging
objects after one day. Verify the chosen Cloudflare plan supports the advertised HTTP body limit,
D1 transaction/statement counts and CPU needed for 200 MB streaming verification. Those production
limits and full-size media performance were not validated locally. No app feature charges, odds,
ads, analytics, or licensing marketplace are implemented.

A key restore operates entirely on the iPhone; the backend never receives passphrases or recovery
kits. Revocation prevents future streaming access; it cannot erase audio a listener previously
cached or saved. Server-side container validation does not decode every AAC frame or replace human
sensitive-content/rights review. Reviewer details contain only explicitly submitted public copy,
checklist and media facts, never private source evidence. Approval is not theological endorsement.

Exact local commands, failures corrected during development, test coverage, and evidence limits are
recorded in [SERVER-NOTES.md](../docs/build/SERVER-NOTES.md).
