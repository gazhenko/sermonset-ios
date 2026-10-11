# Codex brief — community backend (Cloudflare)

You are the backend engineer for the community services of this iOS app. A second Codex session is
building the iOS core client at the same time, and Claude builds every screen and web page. Read:

1. `docs/build/FEATURE-SPEC.md` — the scope, invariants, and ownership. **Authoritative.**
2. `AGENTS.md`, `README.md`, `docs/prototype/CORE-NOTES.md` (existing iOS core API and domain).
3. Product knowledge (read-only): `~/Documents/GitHub/sermonset/docs/{privacy-rights-and-moderation,
   collection-trading-and-atlas,data-model,audio-and-publishing}.md` and the Sept 5 handoff in
   `~/Documents/Obsidian Git/Obsidian Git/obsidian/knowledge-base/wiki/sources/` (§7 invariants, §9).
4. Reference Worker on this machine: `~/Documents/GitHub/ink-drift-tokyo/Relay` (wrangler 4, Durable
   Objects, custom domain on `gazhenko.dev`). Read-only.

## You own
`server/**`, `docs/api/**`, `docs/adr/0004-cloudflare-backend.md`, `docs/build/SERVER-NOTES.md`.
Do not edit anything else (in particular `Packages/`, `SermonSet/`, `web/`, `project.yml`).

## Step 1 — the contract (do this first, within your first hour)
Write `docs/api/API.md`: every endpoint (method, path, auth, request/response JSON with field types,
error shape `{error: {code, message}}`, idempotency, pagination), the request-signing scheme, the offer
token and service-QR token formats (and how to verify them offline with the published keys), signed
audio URL format, state machines (publication, offer), and the **web contract**: which routes serve
Claude's static files from `web/` and which server-rendered pages exist (share page, print view for
service QR) with the exact template variables Claude must use. The iOS core session builds its client
against this file as soon as it appears, so keep it accurate and versioned (`API-VERSION: 1`); record
later changes in a changelog section at the bottom.

## Step 2 — build it
- `server/`: TypeScript Worker (Hono or plain fetch router — your call), D1 migrations in
  `server/migrations/`, R2 bucket bindings (`AUDIO`, `IMAGES`), Cron Trigger (weekly Sunday Pack pool,
  hourly offer expiry, journey cohort recompute), Workers static assets from `../web` (Claude's).
- Everything in FEATURE-SPEC §2–§10 that is server-side: accounts & signed requests & replay protection,
  recovery support, roles, web sessions (link-a-browser codes, admin bootstrap secret via `wrangler secret`),
  publishing + upload lifecycle + validation + canonical matching, community discovery/search/church pages,
  signed audio URLs with rights re-check, card editions/instances/serials, offers (gift/swap) with atomic
  compare-and-swap transfers and idempotency keys, blocking, inbox events, Sunday Pack generation and
  per-account deterministic packs, community Atlas aggregation, opt-in card journeys with cohort
  suppression, reports, moderation queues/actions/audit log/appeals, church claims, church portal APIs
  (profile, claim/correct sermons, approve/reject listener recordings, official audio upload & canonical
  switch, removal requests, service QR issuing & revocation with an Ed25519 or P-256 server signing key,
  credit policy), share links (store client-uploaded card PNG + public metadata).
- Brand strings only in `wrangler.toml` vars (`BRAND_NAME`, `BRAND_SCHEME`, `PUBLIC_BASE_URL`).
- Privacy: no request logging of content (`[observability] enabled = false` or equivalent), no IPs stored,
  coarse places only, data deletion on account delete, no analytics.
- Seed: a dev seed script that loads the eight fictional sample sermons (from
  `Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/samples.json`) as published community
  sermons with their audio, plus 3 fictional churches, so discovery, packs, atlas, and trading are
  demonstrable locally. Mark all seed data fictional.

## Step 3 — prove it
- Tests with Vitest + `@cloudflare/vitest-pool-workers` (or Miniflare): every invariant in FEATURE-SPEC,
  especially concurrent/duplicate trade acceptance, expiry/cancel, idempotent retries, notes never present
  in any payload, rights gates before public audio, removal preserving collection history, cohort
  suppression, signature/replay rejection.
- `npm test` must pass; `npm run dev` serves on `127.0.0.1:8787` with local D1/R2 persistence in
  `server/.wrangler` (gitignored). A smoke script (`server/scripts/smoke.mjs`) exercises a full flow:
  two accounts, publish, approve, discover, keep, offer, accept, pack open, report, moderation action.
- **Do not deploy** and do not touch DNS. Write `server/README.md` with exact deploy steps (D1/R2 creation,
  secrets, custom domain) for later; Claude will deploy after the owner approves.

## Rules
No commits or branches. Record exact commands and results in `docs/build/SERVER-NOTES.md` (honest; never
claim an unrun check). Keep the contract file current. End with a summary: what works, test results,
API changes, open risks.
