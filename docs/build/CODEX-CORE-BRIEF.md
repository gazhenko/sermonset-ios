# Codex brief — iOS core for the feature-complete app

You built `Packages/SermonSetCore` (see `docs/prototype/CORE-NOTES.md`, `docs/REVIEW.md`). Now take it to
feature complete. A second Codex session is building the Cloudflare backend in `server/` at the same
time; Claude builds every screen. Read:

1. `docs/build/FEATURE-SPEC.md` — scope, invariants, ownership. **Authoritative.**
2. `docs/api/API.md` — the server contract, written by the server session early in its run. It may not
   exist when you start: do the offline work first (order below) and check for it before networking.
3. Existing code, tests, `docs/prototype/CORE-CONTRACT.md`, and the product docs in
   `~/Documents/GitHub/sermonset/docs` (read-only).

## You own
`Packages/SermonSetCore/**`, `project.yml`, `scripts/**`, `SermonSet/Support/**` (Info.plist,
entitlements), `docs/prototype/CORE-NOTES.md`, `docs/REVIEW.md`. Do not edit `server/`, `web/`,
`docs/api/`, or any SwiftUI under `SermonSet/App|Looks|Components|Features|Resources`, or `SermonSetUITests/`.

## Build order (keep the package compiling and tests green after each step)
1. **Voice Focus** offline DSP derivative + **trim window** + level-matched A/B support + music-section
   detection + diagnostics (FEATURE-SPEC §1). Original stays immutable; derivative has provenance.
2. **Transcript editing** (new revision, evidence revalidation, stale flags) and **locale selection**
   (supported locales, per-sermon language; insights in that language when supported).
3. **Venue suggestion** (one-shot CLLocation → `MKLocalSearch` churches → candidates; precision choice;
   no precise storage). Info.plist: `NSLocationWhenInUseUsageDescription` = "SermonSet suggests the church
   you’re at. Your location is only used for this suggestion and is never saved or shared." (brand word
   will be replaced at rename).
4. **Backup archive**: export the whole library (audio, notes, moments, transcripts, insights, cards) to a
   zip (optionally passphrase-encrypted) and restore/merge without duplicates; the UI presents it with
   `fileExporter`/`fileImporter`.
5. **Service QR tokens**: parse + verify offline against cached server keys (format from API.md); expose
   the decoded grant for the recorder and publish flows. Camera capture UI is Claude's — you take a
   decoded string.
6. **Identity**: P-256 device key in Keychain (Secure Enclave when available), signed request client per
   API.md, account create/update/delete, recovery kit export/import.
7. **Networking + community state** against API.md: base URL configurable (`-SermonSetServer <url>`
   launch arg; default from a single constant), offline-tolerant cache, inbox polling, community library
   entries and owned community cards merged into the store without breaking existing invariants.
8. **Publishing queue**: build the publish payload from a local sermon (metadata, reviewed text, trimmed
   enhanced audio), background `URLSession` uploads, resumable, state tracking per FEATURE-SPEC §3.
9. **Discover / keep / listen** for community sermons (signed audio URLs; unavailable states).
10. **Trading**: offers (gift/swap), accept/decline/counter/confirm/cancel, idempotency, deep-link and
    QR payload parsing (`<scheme>://offer/<token>` and `https://<domain>/t/<token>`), **nearby** exchange
    over MultipeerConnectivity (Info.plist `NSLocalNetworkUsageDescription`, `NSBonjourServices`),
    blocking, per-card history/journeys (opt-in).
11. **Sunday Pack (server)** with bundled-sample fallback, **community Atlas** data, **reports**.
12. **Official audio choice**: when a canonical official master exists, the listener can switch playback
    source with an explicit warning that marked moments may shift; keep personal anchors on the source
    asset; expose an offset/alignment-unavailable state.
13. **Share links**: create share (upload Claude's rendered PNG + public metadata), return URL.
14. `AppBrand`-neutral: URL scheme and display name must come from Info.plist build settings so a rename is
    one change in `project.yml`.

Expose each capability as `@MainActor @Observable` controllers or store APIs the UI binds to. Update
`docs/prototype/CORE-NOTES.md` **as you go** (exact public signatures per step) — Claude builds the UI
from it in parallel, step by step.

## Testing
Swift Testing for every invariant and failure path (DSP output bounds and immutability, evidence
staleness, archive round-trip/merge, QR signature failure/expiry, request signing, offline queue retry,
idempotent trade calls, notes never serialized into any network payload, rights-gated audio states).
Integration tests against a local server: run your own instance with
`cd server && npx wrangler dev --port 8788 --persist-to ../build/wrangler-core` (the server session uses
8787; never stop its process). If the server isn't ready yet, test with `URLProtocol` stubs and come back.

## Rules
Simulator `32502FB1-1CBE-4555-B1FE-CF1712B1A45C` and `build/DerivedData-core` only. No third-party
packages. No commits. Record exact commands and results in `docs/REVIEW.md`; never claim unrun checks;
simulator results are not device evidence. End with a summary of what works, API changes, tests, risks.
