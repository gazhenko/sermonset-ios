# Server implementation and verification

Date: 2026-10-05. Assignment: CODEX-SERVER-BRIEF.md and authoritative FEATURE-SPEC.md, including the
owner's BRAND.md decision and Claude's WEB-REQUESTS.md. All authored changes are inside `server/**`,
`docs/api/**`, this file, and `docs/adr/0004-cloudflare-backend.md`. The other owners' changes in
Packages/, SermonSet/, web/, project.yml, scripts/, and shared documentation were left alone.
AGENTS.md normally requests evidence in docs/REVIEW.md; this assignment explicitly forbids modifying
that shared file, so the complete server evidence is recorded here instead.

## Delivered

- API-VERSION 1 contract published before implementation, with every endpoint, JSON shape, errors,
  pagination, retry semantics, request-signing bytes, JWS offer/service tokens, signed public and
  authenticated reviewer audio, state machines, static routes and exact HTML template variables.
- TypeScript Worker, three D1 migrations, private AUDIO/IMAGES R2 bindings, static asset binding to
  Claude's `../web`, hourly/Sunday cron, disabled observability, no external runtime dependencies.
- Device-key accounts, nonce replay prevention, client-side recovery support, role checks, single-use
  browser codes, CSRF-protected strict cookies, secret-only admin bootstrap and account deletion.
- Explicit reviewed publishing, immutable bounded streaming uploads, incremental SHA-256, AAC/MP4
  structural and measured-duration validation, private quarantine, church/QR/official scoped grants,
  transaction-safe canonical matching and official replacement. Rights checked on URL issue and use.
- Discovery/search/filtering, church pages, card editions/serials/instances, permanent community
  library entries, signed gifts and swaps, atomic version-checked transfers and retry receipts,
  blocking, ownership history, inbox and deterministic diverse weekly packs with small-pool labels.
- Public city/church Atlas, default-off journeys with every-participant consent/hide-past and dynamic
  three-card cohort suppression, and default-off named contribution credit under church policy.
- Reports, queue context and protected audio preview, moderation decisions/audit/appeals, verified
  church claims, profiles, unassigned-sermon claims, moderator attribution correction, listener
  approval/rejection, official masters, immediate takedown, revocable/printable signed service tokens.
- Checksum-verified PNG shares, escaped server templates, configured deep links, static `/church`,
  `/moderate`, `/t/:token` routing, and legacy `/portal`/`/moderation` aliases.
- Fictional dev seed: eight actual bundled M4A files and their public sermon metadata, three fictional
  church networks, eight original city-level venues. No sample notes/transcripts/moments imported.
- README with local commands and exact later D1/R2 creation, secrets, migrations, custom-domain
  deployment and bootstrap-secret removal instructions. ADR records the platform and privacy choices.

## Exact successful commands and outcomes

All commands below used the cached tools, without installing dependencies. Node v22.23.1, npm
10.9.8, Wrangler 4.147.0, Miniflare 5.20261001.0-alpha, esbuild 0.28.1. The ignored node_modules
symlink points at the read-only reference Relay cache; package-lock.json was derived from that
existing, matching dependency graph. Miniflare's v4-options adapter is required by the cached v5
alpha. The test runner is node:test + Miniflare, using the brief's Miniflare alternative to Vitest.

| Working directory | Exact command | Outcome |
| --- | --- | --- |
| Repository | `ln -s /Users/jemmygazhenko/Documents/GitHub/ink-drift-tokyo/Relay/node_modules server/node_modules` | Reused existing toolchain; no install. |
| server | `node scripts/local-keys.mjs` | Generated disposable local signing/bootstrap/capability fixtures in ignored .dev.vars, mode 0600. Correct dotenv quoting is single quotes around JSON values. |
| server | `npm run migrate` | Applied 0001 and 0002 to local D1 after correcting the binding name to DB. |
| Repository | `npm --prefix server run migrate` | Applied 0003 (credit and ownership-event ledger); later run correctly reported no migrations to apply. |
| server | `npm run seed` | 35 local SQL seed commands succeeded; all eight R2 audio objects uploaded; three fictional church networks. |
| Repository | `npm --prefix server run dev` | Ready at http://127.0.0.1:8787 with local D1/R2 persistence, static web assets, and hidden local fixture secrets. Restarted after correcting dotenv values. |
| Repository | `npm --prefix server run check` | PASS: esbuild bundled the production TypeScript Worker; observability remains disabled. This is a bundle/syntax check, not a TypeScript typecheck. |
| Repository | `npm --prefix server test` | Final PASS: 40/40 tests, 0 failures/skips, about 31.2 s. Actual production code with disposable Worker/D1/R2 bindings and every migration. |
| Repository | `npm --prefix server run smoke` | Final PASS on the persisted live dev server: two accounts, actual audio upload, rights gate/approval, discover/keep, gift + retry, pack open, ranged playback, report, takedown; both histories and recipient card preserved; all static routes served. |
| Repository | `git diff --check -- server docs/api docs/adr/0004-cloudflare-backend.md docs/build/SERVER-NOTES.md` | PASS, no whitespace errors. |
| Repository | `git check-ignore server/node_modules server/.tmp server/.dev.vars server/.wrangler/state` | PASS: all four ignored, including the cached-toolchain symlink. |

The formatter command was run using an already-cached Prettier binary, with only owned inputs:

```sh
node /Users/jemmygazhenko/.npm/_npx/b388654678d519d9/node_modules/prettier/bin/prettier.cjs --write 'server/src/*.ts' 'server/scripts/*.mjs' 'server/test/*.{mjs,ts}' server/package.json
```

The two real Wrangler local scheduled hooks were also invoked, using exactly this Node program
from the repository. Both returned HTTP 200, body `ok`:

```sh
node - <<'JS'
for(const cron of ['0 0 * * SUN','0 * * * *']){
 const r=await fetch('http://127.0.0.1:8787/cdn-cgi/local/scheduled?cron='+encodeURIComponent(cron));
 const body=await r.text();console.log('Local cron',cron,r.status,body.slice(0,100));
}
JS
```

The owned local dev process was stopped after verification. No shared simulator, credential store,
DNS, remote resource, deployment, branch, or commit was changed. Tests generate their own identities
and local fixtures; no production signing keys or existing remote credentials were used.

## Test coverage

| Invariant / behavior | Evidence |
| --- | --- |
| Atomic gifts and both swap legs; libraries remain independent | trading.test.mjs checks owners, versions, histories, swap proposal/confirmation and participant-only ledger. |
| Duplicate/concurrent trade acceptance, CAS, expiry/cancel/decline | Eight concurrent same-key accepts, competing offers, different-key duplicate accepts, stale swap rollback including no retry receipt, unchanged ownership for terminal offers. |
| Private material never enters server state or payload projections | community.test.mjs rejects notes, moments, transcripts, drafts, originals, coordinates and playback data; inspects feeds, cards, library, inbox and review queues; seed contains no private sample fields. |
| Recording permission differs from redistribution | publishing.test.mjs and trust-web.test.mjs reject no-rights audio and recording-only QR, require reviewed checklist/trim provenance and validated AAC, keep review-required uploads unavailable. |
| Original/derivative distinction and immutable uploaded media | Source-checksum provenance required, unchanged-original uploads rejected, checksum corruption/false codec/duration rejected; completed upload retry preserves stored bytes. No server path accepts private originals. |
| Canonical matching and replacement preserve history/evidence context | Concurrent matching creates one sermon; verified official master changes canonical ID and returns the moments-shift warning while cards/history remain. |
| Rights withdrawal beats issued links and does not erase collections | Takedown/QR revoke makes issued streaming links unavailable; cards and both libraries survive; expired/wrong-church grants cannot restore playback. |
| Free weekly deterministic pack and public Atlas | Frozen five-card allocation, library exclusion, distinct church preference, concurrent open once, current-week enforcement, labelled small-pool fallback; Atlas has public city counts only. |
| Journey privacy | Under-three suppression, every participant's opt-in, hide-past, unconsenting onward recipient, and immediate suppression despite stale cron cohort cache; public output has only city/week. |
| Identity, replay, recovery and browser roles | Signature covers method/path/query/account/body, skew and nonce rejection, re-registration restores identity, registration idempotency conflicts, single-use codes, strict cookies, Origin + CSRF, moderator/staff/admin checks. |
| Moderation and church tools | Reports/timestamps/target summaries, claim approval, scoped profiles/corrections, audited rejection/appeal, ban/unban, inbox read, protected reviewer preview, impossible transition rejection, metadata restore. |
| Service/offer tokens and web pages | Independent offline P-256 verification against published keys, tampering rejection, printed service role gate, configured scheme, escaped share template, validated PNG, static route headers. |
| Account deletion | Owned state/credit removed, audio object deleted through durable cleanup jobs, other owners' history/cards retained and audio unavailable. |
| No server AI/cloud transcript fallback | No transcript/draft fields or processing endpoints; reviewed public summary is a separate input. Native AI evidence validation is the core owner's responsibility. |

## Failures corrected during implementation

The final gates above are separate from these unsuccessful intermediate commands; none were counted
as passing results.

- The first `npm test` (server cwd) failed 0/2 because the installed Miniflare v5 alpha requires the
  exported v4-options conversion. After using that adapter, identity tests passed 2/2.
- The first expanded `npm test` passed 11/14. R2 requires a known-length stream, and the AAC descriptor
  parser needed variable-length MPEG-4 descriptor sizes. FixedLengthStream and a structural AAC
  parser resolved both; targeted `node --test test/publishing.test.mjs` then passed 4/4.
- The next full `npm test` passed 30/31. The browser-session promise needed awaiting inside the top
  JSON error handler. The corrected run passed 32/32, then later expanded runs passed 37/37 and 40/40.
- One early `npm run migrate` used the obsolete COMMUNITY binding and failed to find migrations.
  package.json/seed now use DB and the generated config has absolute migration paths. Final local
  migrations all applied successfully.
- Smoke first found a long LIKE-pattern query failure in real local D1; discovery and church search
  now use literal case-insensitive substring matching. A regression covers a full UUID-length title
  with percent/underscore characters. An early repeated smoke also matched a previous canonical
  passage; each smoke run now has a unique fictional title and passage.
- Subsequent smoke uncovered invalid dotenv quoting of local JWK JSON and a stale dev process's
  loaded fixture secrets. The generator now single-quotes JSON; restarting the owned server fixed
  signing keys. Final smoke and GET /v1/keys both succeeded. Local config/secrets are written only
  when changed, avoiding unnecessary reloads during a local D1 fixture command.
- A setup heredoc mistakenly used repository-prefixed server paths from server cwd; no files were
  created by that failed attempt. Commands were corrected to the repository cwd. Bare `npm test`
  and `npm run smoke` from the repository root failed ENOENT because this is a server subproject;
  successful root commands use `npm --prefix server ...`.
- `node server/node_modules/.bin/esbuild ...` failed because that cached entry is a native executable.
  The production check and test harness use esbuild's JS API and both passed.
- Initial Wrangler operational logs used its default global directory. The local wrapper now directs
  logs and registry into ignored server/.tmp, hides its update-check banner and disables metrics and
  local observability/explorer. The symlink-specific ignore rule was corrected and verified.

## API changes and remaining evidence limits

API version remains 1. Changelog records additive reviewer details/preview URLs, report targetSummary,
Sower routes, default-off creditOptIn, ownership history, church claims and moderator corrections,
and the browser logout idempotency-header exception. Existing signing and token formats did not change.
The contract was kept current for the parallel core/web sessions; their local Swift/UI files were
not modified, and their end-to-end integration/hardware validation was not claimed.

Blocked/unrun deployment checks: actual Cloudflare provisioning and custom-domain deployment
(intentionally not authorized), production resource/HTTP body/CPU/transaction limits, full 200 MB
and three-hour audio stress runs, production key rotation, R2 staging lifecycle configuration,
real church/rightsholder verification and operational/legal readiness. These are documented later
operator checks, not fabricated passes. No formal tsc check was possible with the cached tools;
TypeScript bundling and runtime integration tests passed. Physical iPhone, native recovery-kit,
Secure Enclave, offline caching and UI accessibility checks belong to the other owners and remain
outside this server evidence.

Container validation verifies format structure, integrity, one AAC track and measured duration;
it does not decode every AAC frame, assess loudness, or detect every sensitive passage. Human
review and scoped permission remain mandatory. Partial staging data abandoned by process loss needs
the documented private R2 lifecycle rule. Revocation blocks future server reads but cannot erase
previously saved client audio. Pagination is an offset snapshot; concurrent changes may require a
fresh fetch. Packs use simplified Western liturgical seasons and public library venues for local
preferences; they do not request or store listener location. Production abuse throttling/resource
quotas should be chosen before broadly opening registration/public submissions.

Final production-entry sanity check (repository cwd) also passed:

```sh
node - <<'JS'
import {readFile} from 'node:fs/promises';
const bundle=await readFile('server/.tmp/worker.mjs','utf8');
if(bundle.includes('/__fixture/'))throw Error('Test entrypoint leaked into production bundle');
console.log('Production bundle excludes test fixture routes.');
const config=await readFile('server/wrangler.toml','utf8');
console.log('Owned Worker config present:',config.includes('enabled = false'));
JS
```

Final scoped `git status --short --untracked-files=all -- server docs/api
docs/adr/0004-cloudflare-backend.md docs/build/SERVER-NOTES.md` listed authored source/docs only;
no cached dependencies, signing fixtures, local database/object data, or generated bundles were exposed.

## Local dev: strip production routes (2026-10-05)

Implemented the final request in `docs/build/WEB-REQUESTS.md`. `scripts/dev.mjs` removes the
production `routes` array (including its `custom_domain`) and `workers_dev` before writing the
derived `.tmp/wrangler.local.toml`. The array removal supports inline and multiline assignments.
The existing loopback `PUBLIC_BASE_URL`, brand values, absolute resource paths, bindings, assets,
cron, and disabled observability behavior are retained. Production `wrangler.toml` is unchanged.

`test/dev.test.mjs` runs the actual wrapper and production Worker against a fresh local D1 database
with every migration applied. Its fixture copies only server source/config/scripts/migrations and
creates a minimal static asset fixture; it reuses the cached node_modules. All fixture config,
logs, registry, and persistence live under ignored `build/wrangler-codex/dev-wrapper-*`. It does
not copy existing `.dev.vars` or use the shared local database.

The test connects its HTTP socket exclusively to **127.0.0.1:8795**, while explicitly sending
`Host: 127.0.0.1:8787` and `Origin: http://127.0.0.1:8787`. This reproduces the configured console's
same-origin request through Wrangler without contacting the other session's port 8787. Node's
`fetch` ignored the custom Host header in initial test development, so this request uses
`node:http.request`; a mismatched transport Origin alone would not exercise Wrangler's rewrite.
With the original wrapper, the final regression request returned HTTP **403** and
`Open the console on its configured origin.` With the fix, it returns **200**, the correct account,
a CSRF token, and an HttpOnly/SameSite=Strict cookie that authenticates `/v1/me`. Code reuse returns
401 and a foreign Origin returns 403. The test also checks that the derived config has no
`routes`, `custom_domain`, or `workers_dev`, retains the local origin/brand/assets/observability,
and leaves both the fixture and original production config byte-identical.

The test checks that port 8795 is available before starting. It registers cleanup hooks that signal
only the process groups it creates, including on assertion failure. No process on port 8787 was
stopped, restarted, or contacted, and the shared `server/.tmp/wrangler.local.toml` was not rewritten.
The existing listener remained `workerd` PID **88390** before and after validation. No dependency
installation, deployment, commit, or changes to `web/`, `Packages/`, `SermonSet/`, or `site/` occurred.

| Working directory | Exact command | Result |
| --- | --- | --- |
| server | `node --test test/dev.test.mjs` (before fix) | Expected failure: 0/1, HTTP 403 instead of 200. Two earlier harness attempts using fetch failed the config assertions; neither was a passing regression run. |
| server | `node --test test/dev.test.mjs` (after fix) | PASS: 1/1, 0 failures/skips, 3.27 s, exit 0. |
| server | `node /Users/jemmygazhenko/.npm/_npx/b388654678d519d9/node_modules/prettier/bin/prettier.cjs --write scripts/dev.mjs test/dev.test.mjs` | PASS: formatted only the two changed server files using the cached binary, exit 0. |
| server | `npm test` | PASS: 41/41, 0 failures/cancellations/skips, 44.65 s, exit 0; includes the real-wrapper sign-in regression. |
| server | `npm run check` | PASS: production TypeScript Worker bundled; observability disabled, exit 0. This is esbuild validation, not a full TypeScript typecheck. |
| Isolated `build/wrangler-codex/dev-wrapper-*/server` fixture, invoked by test | `node scripts/dev.mjs d1 migrations apply DB --local --persist-to ../build/wrangler-codex` | PASS: all three migrations applied to the fresh fixture D1 database, exit 0. |
| Same isolated fixture, invoked by test | `node scripts/dev.mjs dev --local --ip 127.0.0.1 --port 8795 --inspector-port 0 --persist-to ../build/wrangler-codex` | PASS: ready, real sign-in/cookie/code-reuse/foreign-origin assertions passed; test stopped only its own process group. The relative persistence path is inside this ignored fixture. |
| Repository | `lsof -nP -iTCP:8787 -sTCP:LISTEN` | Original listener PID 88390 remains unchanged. |
| Repository | `lsof -nP -iTCP:8795 -sTCP:LISTEN` | No listener after test cleanup (empty output, lsof exit 1). |
| Repository | `git diff --check -- server docs/build/SERVER-NOTES.md docs/REVIEW.md` | PASS: exit 0. Existing server/ and build-doc files are untracked in this shared workspace. |

## Don't notify people about their own actions (2026-10-05)

Implemented the final section of `WEB-REQUESTS.md`, including matching publication and moderation
writers. `common.ts` now takes the authenticated request context for inbox events and excludes its
actor in the INSERT itself. Offer creation still notifies the recipient. Cancellation, decline,
proposal, gift acceptance, and swap confirmation notify only the other party, including bearer
offers whose recipient becomes known during the action. Cancelling an unclaimed bearer offer
creates no notification. Scheduled expiry has no account actor and still notifies both parties.

Publication submission/upload completion, report submission, and church removal no longer create
notifications for their actor. Publication approval/rejection, church decisions, claim decisions,
report/appeal resolutions, and sermon/audio moderation use the same actor-aware writer. Other
contributors and affected accounts retain their existing notifications, and audit records remain.
Automatic official/QR publication approval also excludes the contributor performing completion.

Migration `0004_actor_notifications.sql` replaces the original offer-transfer trigger to remove its
two unconditional inbox INSERTs. Acceptance notifications now belong to the request's existing
atomic command batch alongside ownership changes and its retry receipt. A source comparison verified
every transfer guard and ownership mutation is byte-identical to the original trigger. Existing
databases need this migration when adopting the updated Worker. The shared database was not migrated.

`test/inbox.test.mjs` exercises 30 scenarios through the real Worker and D1: bound/bearer offer
actions and retries; moderator/church approval and rejection of one's own or another contributor's
publication; own/other claim, report, and appeal resolution; and own/other sermon dispute, removal,
and restoration. It checks actual stored inbox rows and unchanged actor inbox responses. Existing
tests additionally cover concurrent acceptance exactly once, failed swap rollback without an inbox
event, upload completion/automatic official approval, church removal, and actorless expiry exactly
once for both participants. No test-only notification endpoint or runtime instrumentation was added.

The first regression run reproduced self-notifications (6/39 passing, 33 failures, including parent
subtest failures). The first run after the fix passed 37/39: the remaining scenario reused another
contributor's canonical sermon because matching uses either title or passage. Giving that fixture
both a distinct title and passage resolved its isolation error; the final focused run passed 39/39.
No unrelated canonical-matching behavior was changed.

All build/test commands below ran from `server/`, using cached dependencies without installation or
external network access. Output logs and snapshots are under ignored `build/wrangler-codex`; bundles
remain under ignored `server/.tmp`. This task's evidence is recorded here as requested, leaving the
existing shared `docs/REVIEW.md` alone.

| Exact command | Result |
| --- | --- |
| `node --test --test-concurrency=1 test/inbox.test.mjs test/publishing.test.mjs > ../build/wrangler-codex/self-inbox-before-tests.log 2>&1` | Expected regression failure: 6/39 passing, 33 failing, 10.57 s, exit 1. |
| `node --test --test-concurrency=1 test/inbox.test.mjs test/publishing.test.mjs > ../build/wrangler-codex/self-inbox-after-tests.log 2>&1` | Final PASS: 39/39, 0 failures/cancellations/skips, 11.61 s, exit 0. Intermediate fixture-isolation failure described above. |
| `node /Users/jemmygazhenko/.npm/_npx/b388654678d519d9/node_modules/prettier/bin/prettier.cjs --write src/common.ts src/offers.ts src/publishing.ts src/moderation.ts test/inbox.test.mjs test/trading.test.mjs test/publishing.test.mjs test/community.test.mjs` | PASS: formatted only owned changed server files using the cached binary, exit 0. |
| `node /Users/jemmygazhenko/.npm/_npx/b388654678d519d9/node_modules/prettier/bin/prettier.cjs --write test/inbox.test.mjs test/trading.test.mjs` | PASS: formatted final fixture/rollback assertion changes, exit 0. |
| `npm test > ../build/wrangler-codex/self-inbox-npm-test.log 2>&1` | PASS: 75/75 (45 top-level tests and 30 subtests), 0 failures/cancellations/skips, 46.72 s, exit 0. Includes all four migrations and the real dev-wrapper regression. |
| `npm run check` | PASS: production TypeScript Worker bundled; observability disabled, exit 0. This is the existing esbuild check, not a full TypeScript typecheck. |

The full suite's dev-wrapper test copied source/config/migrations into its own ignored fixture and
used these exact commands from that fixture's `server/` directory:

```sh
node scripts/dev.mjs d1 migrations apply DB --local --persist-to ../build/wrangler-codex
node scripts/dev.mjs dev --local --ip 127.0.0.1 --port 8795 --inspector-port 0 --persist-to ../build/wrangler-codex
```

All four migrations applied successfully, and the test stopped its own Wrangler process group.
Miniflare integration harnesses used disposable databases and were disposed by test cleanup. No
requests, stop/restart signals, or persistence mutations were sent to the other session on port
8787. Repository-level `lsof -nP -iTCP:8787 -sTCP:LISTEN` showed the same `workerd` PID **5510** before
and after the work. `lsof -nP -iTCP:8795 -sTCP:LISTEN` returned no listener afterward (empty output,
exit 1). `git check-ignore build/wrangler-codex server/.tmp` confirmed both generated-output roots
are ignored (exit 0). `git diff --check -- server docs/build/SERVER-NOTES.md` passed (exit 0).
The new untracked files were also checked with `git diff --no-index --check -- /dev/null
server/test/inbox.test.mjs` and `git diff --no-index --check -- /dev/null
server/migrations/0004_actor_notifications.sql`; both had empty output and exit 1 for file differences,
with no whitespace diagnostics.

Authored changes are limited to `server/**` and this appendix. No deployment, commit, dependency
installation, or modification of `web/`, `Packages/`, `SermonSet/`, or `site/` was performed.

## Production D1 trigger migration compatibility (2026-10-05)

Implemented the final section of `docs/build/WEB-REQUESTS.md`. Rewrote the seven offer-transfer
guards in each of `0001_community.sql` and `0004_actor_notifications.sql` from
`SELECT CASE WHEN condition THEN RAISE(ABORT,'error') END;` to
`SELECT RAISE(ABORT,'error') WHERE condition;`. Both forms abort only when the condition is true;
false and SQL NULL conditions do not abort. The predicates, guard order, error strings, ownership
updates, and migration-specific notification behavior are preserved. The initial migration retains
its inbox INSERTs; 0004 retains their removal. No trigger body now has an inner line ending in
`END;`. The other triggers, including those in 0003, already met this requirement.

`test/migrations.test.mjs` discovers every SQL migration and uses the installed Wrangler SQL
splitter, which respects quoted strings and comments. It checks that every trigger definition is
retained, has its own standalone closing END, and has no inner `END;` line. A second test executes
every split statement individually against a fresh in-memory SQLite database and verifies all five
final triggers exist. The structural assertion reproduced the reported incompatible pattern in
both 0001 and 0004 before the rewrite. The existing Worker/Miniflare trigger and integration tests
were left unchanged and all pass, including transfer retries/concurrency, failed swap rollback,
mint serials, ownership/library/journey history, notifications, and actorless expiry.

A snapshot comparison in the ignored workspace independently verified exactly 14 mechanical guard
rewrites and no other byte changes in any migration. All four migrations are included in validation.
No dependencies were installed and no external network access was required. Node 22.23.1 prints
its normal experimental SQLite warning for the new in-memory test; no check failed or was skipped.

Build/test commands below ran from `server/`. Logs, original migration snapshots, and the temporary
comparison script are under ignored `build/wrangler-codex`; generated bundles remain in ignored
`server/.tmp`. This task's commands and evidence are recorded here as requested.

| Exact command | Result |
| --- | --- |
| `mkdir -p ../build/wrangler-codex/trigger-migrations-before && cp migrations/*.sql ../build/wrangler-codex/trigger-migrations-before/` | PASS: saved the original four migrations before editing, exit 0. |
| `node --test test/migrations.test.mjs > ../build/wrangler-codex/trigger-migrations-before-test.log 2>&1` | Expected failure: the 0001 and 0004 structural subtests fail on inner END; lines. 3/6 checks pass; 3 fail including the parent test, 0.83 s, exit 1. Wrangler-split local SQLite application already passed, demonstrating why local application alone is insufficient. |
| `node /Users/jemmygazhenko/.npm/_npx/b388654678d519d9/node_modules/prettier/bin/prettier.cjs --write test/migrations.test.mjs` | PASS: formatted only the new test with the cached formatter, exit 0. |
| `node --test --test-concurrency=1 test/migrations.test.mjs test/trading.test.mjs > ../build/wrangler-codex/trigger-migrations-focused-test.log 2>&1` | PASS: 15/15 checks, 0 failures/cancellations/skips, 9.01 s, exit 0. |
| `python3 ../build/wrangler-codex/verify-trigger-rewrite.py` | PASS: seven guard rewrites each in 0001 and 0004; all other migration bytes identical, exit 0. |
| `npm test > ../build/wrangler-codex/trigger-migrations-npm-test.log 2>&1` | PASS: 81/81 checks (47 top-level tests and 34 subtests), 0 failures/cancellations/skips, 46.57 s, exit 0. |
| `npm run check > ../build/wrangler-codex/trigger-migrations-npm-check.log 2>&1` | PASS: production TypeScript Worker bundled; observability disabled, exit 0. This is the existing esbuild check, not a full TypeScript typecheck. |

The full suite's existing dev-wrapper test applied all four migrations in its own ignored fixture,
started Wrangler on port 8795, and stopped its own process group. It used these commands from the
fixture's `server/` directory, with persistence contained inside that fixture:

```sh
node scripts/dev.mjs d1 migrations apply DB --local --persist-to ../build/wrangler-codex
node scripts/dev.mjs dev --local --ip 127.0.0.1 --port 8795 --inspector-port 0 --persist-to ../build/wrangler-codex
```

Repository-level `lsof -nP -iTCP:8787 -sTCP:LISTEN` showed the same `workerd` PID **5510** before
and after validation (exit 0). Port 8787 was not contacted, stopped, or restarted.
`lsof -nP -iTCP:8795 -sTCP:LISTEN` returned no listener afterward (empty output, exit 1).
`git check-ignore build/wrangler-codex server/.tmp` confirmed both generated-output roots are
ignored (exit 0). `git diff --check -- server docs/build/SERVER-NOTES.md` passed (exit 0).

The four untracked authored files also produced no whitespace diagnostics with the following
repository-level commands; each exited 1 for file differences:

```sh
git diff --no-index --check -- /dev/null server/migrations/0001_community.sql
git diff --no-index --check -- /dev/null server/migrations/0004_actor_notifications.sql
git diff --no-index --check -- /dev/null server/test/migrations.test.mjs
git diff --no-index --check -- /dev/null docs/build/SERVER-NOTES.md
```

Remote production D1 validation remains unrun, as requested; the structural regression, SQLite
application test, and local D1 integration evidence do not claim a remote migration pass.
Authored changes are limited to the two server migrations, the new server test, and this appendix.
No deployment, remote command, commit, credentials access, or changes to `web/`, `Packages/`,
`SermonSet/`, or `site/` were performed.

## Uppercase brand expectation (2026-10-05)

Updated `test/dev.test.mjs` to expect `BRAND_NAME = "SOWER"` in the generated local config.
The owner's existing `wrangler.toml` is byte-for-byte unchanged, preserving the lowercase
`sower` scheme and Worker name, `sower-db`/`sower-audio`/`sower-images` resources, and domain.
An audit of server source files, tests, fixtures, fallback pages, and README found no other
mixed-case brand expectation. Fallback page titles already interpolate `BRAND_NAME`.

Commands ran from `server/`, using the existing dependencies and ignored output directories:

| Exact command | Result |
| --- | --- |
| `npm test > ../build/wrangler-codex/brand-uppercase-npm-test.log 2>&1` | PASS: 81/81 tests (47 top-level tests and 34 subtests), 0 failures/cancellations/skips, 49.56 s, exit 0. Includes the real dev-wrapper regression. |
| `npm run check > ../build/wrangler-codex/brand-uppercase-npm-check.log 2>&1` | PASS: production Worker bundle compiled; observability disabled, exit 0. This is the existing esbuild check, not a full TypeScript typecheck. |

The dev-wrapper test started its isolated local Worker on port 8795 and stopped its own process
group. Repository-level `lsof -nP -iTCP:8795 -sTCP:LISTEN` returned no listener before or after
validation (empty output, exit 1). No connection or process operation targeted port 8787.
No deployment, remote command, dependency installation, commit, or changes to `web/`, `Packages/`,
`SermonSet/`, or `site/` were performed. Validation is also recorded in `docs/REVIEW.md` as required
by the working agreement.
