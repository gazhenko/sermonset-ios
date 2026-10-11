# ADR 0004 — Community backend on Cloudflare

Status: accepted implementation, production deployment pending owner approval.
Date: 2026-10-05.

The community slice needs explicit publishing, verified media permission, unique card ownership,
retry-safe trades, church review, takedown, discovery, weekly packs, and an inbox. Private capture
and backup remain entirely on the device. Apple Developer Program services are outside this slice.

Use a TypeScript fetch Worker, D1/SQLite, two private R2 buckets, Workers static assets, and hourly
and Sunday Cron Triggers. The owner-selected name and scheme come from wrangler.toml; the custom
domain is configured there for later deployment. No deployment, DNS edits, production credentials access,
release signing, branch creation, or commits were performed.

D1 batch transactions serialize mutations. Ownership version assertions, transfer triggers, both
swap legs, library insertions, immutable ownership events, journey events, inbox entries, and an
idempotency receipt commit together. Durable Objects add no benefit for this database-owned ledger.
A withdrawn recording never deletes cards or library history. New verified official audio may change
the canonical pointer; clients keep their marker source and choose whether to switch.

A P-256 device public key identifies an account; signatures cover exact request bytes, target,
account, timestamp, and nonce. Recovery restores the same key on the client. Browser sessions use
single-use app codes, HttpOnly SameSite=Strict cookies, same-origin and CSRF checks, and role checks.
Production bootstrap and signing keys are Worker secrets. Tests generate disposable local fixtures.

R2 is never public. Streaming SHA-256 and bounded MP4 metadata parsing validate upload integrity,
AAC format and duration without buffering the entire recording. Public playback requires an active,
scoped grant both when issuing and redeeming a five-minute HMAC link. Reviewer audio additionally
requires the issuing reviewer's authenticated identity and current role. P-256 JWS service/offer
payloads can be verified offline using cached published keys; revocation is checked online.

No raw transcripts, local originals, notes, moments, AI drafts, listener coordinates, listening
progress, IPs, or analytics are accepted or stored. Public copy is a separate reviewed submission.
Contribution names default off and require both account opt-in and church credit policy. Journey
cohorts require three distinct consenting cards per city; every participant must still consent and
hide-past must be respected. Query-time checks prevent stale hourly aggregates from revealing traces.
Account deletion removes owned state, credit, and uploaded media, and anonymizes surviving public
references needed by other owners' collections. R2 cleanup is durable and retried by cron.

The runtime has no npm dependencies. Development uses the already-cached Wrangler/Miniflare/esbuild
versions recorded in server/package-lock.json. Miniflare executes the actual Worker, D1 triggers,
and R2 requests; node:test drives the assertions without adding another dependency. A local persisted
Wrangler smoke run is a separate gate. Production quotas, full-size upload performance, real church
verification and operational/legal review remain deployment checks. Simulator and physical-iPhone
validation belong to the other owners and are not inferred from server results.
