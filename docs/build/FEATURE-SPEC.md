# Feature-complete specification

This turns the product docs (`~/Documents/GitHub/sermonset/docs`, the Sept 5 handoff) into a buildable
scope. **The app is named Sower** (see `docs/build/BRAND.md`); code keeps the codename `sermonset` in
module names, and **every user-visible brand string lives in one place** (iOS: `AppBrand`; server: `BRAND_*` vars in
`wrangler.toml`; web: one `brand.json`). Renaming must be a one-line change plus regenerated assets.

## Ownership

| Area | Owner |
| --- | --- |
| `server/` — Cloudflare Worker API, D1 schema & migrations, R2 storage, cron jobs, signing keys, server tests | **Codex (server)** |
| `Packages/SermonSetCore/` — domain, persistence, capture, playback, AI adapters, networking client, identity, sync, publishing queue, trading, Voice Focus DSP, location, backup archive, QR token verification, Multipeer transport, deep-link parsing, tests; `project.yml`, `scripts/`, Info.plist | **Codex (core)** |
| `SermonSet/App, Looks, Components, Features, Resources`, `SermonSetUITests/`, `web/` (church portal, moderation console, share pages — all HTML/CSS/JS), icons, copy, trailer, README | **Claude** |

Contracts between owners are written down before code: `docs/api/API.md` (server ↔ core and server ↔
web), `docs/prototype/CORE-NOTES.md` (core ↔ iOS UI). Deviations go in those files with exact shapes.

## Platform decisions (recorded in `docs/adr/0004-cloudflare-backend.md` by Codex)

- **Backend: Cloudflare Workers (TypeScript) + D1 (SQLite) + R2 (audio, card images) + Cron Triggers.**
  Durable Objects only where serialization is genuinely needed. Chosen because it runs and tests locally
  (`wrangler dev`/Miniflare), needs no Apple Developer Program membership (CloudKit would), the owner
  already deploys Workers on the `gazhenko.dev` zone, and the schema is plain SQL (portable to Postgres;
  `workerd` is self-hostable). No vendor SDKs beyond what Workers provides; small, audited npm deps only.
- **No Apple Developer Program features yet:** no push notifications, Sign in with Apple, universal links,
  CloudKit, or App Store. Use: device-key identity, an in-app inbox polled on foreground, a custom URL
  scheme (`sermonset://…`, brand-configurable), and https share pages that link into the app.
- **iOS:** iOS 26, Swift 6, no third-party packages. Simulator is the test target; physical-iPhone checks are
  listed as outstanding, never claimed.

## Invariants (unchanged from the product docs; tests must cover them)

1. Trading moves a Card Instance; it never removes a sermon from anyone's library or moves notes,
   moments, transcripts, or private audio. Ownership changes are atomic, versioned (compare-and-swap),
   idempotent, and expire/cancel without side effects.
2. Private material (recordings, transcripts, notes, moments, drafts, precise location, playback history)
   never leaves the phone unless the listener explicitly publishes or backs it up. No analytics of content.
3. Recording permission ≠ redistribution permission. Public full-sermon audio requires a verified grant
   (church service QR permitting sharing, church approval, or church-uploaded official audio).
4. AI output stays a draft until kept, cites evidence, never invents quotes.
5. Original audio is immutable; derivatives keep provenance.
6. Location suggests context, never permission; public places are church/city level, never the listener.
7. Everything is free: no purchases, ads, odds, or paid rarity.

## Features

### 1. Capture and revisit (done; harden)
Recording, recovery, import, playback, moments, notes, transcript, evidence-linked takeaways, cards,
four looks — as built. Add:
- **Voice Focus** (core DSP + UI): offline-rendered enhanced derivative (high-pass ~80 Hz, gentle presence
  EQ, light downward expansion/noise gate, compression, loudness normalization to −16 LUFS, true-peak
  limiter). Strength 0–100 %. Level-matched A/B at the same timestamp; revert; original untouched.
  Detect likely music sections (high spectral flatness / sustained tonal energy) and leave them unprocessed
  by default. Diagnostic report: clipping %, dropouts, applied gain.
- **Trim sermon boundaries** without touching the original (start/end offsets on a derivative/playback
  window); a trim is required before publishing audio.
- **Transcript editing:** edit a segment → new transcript revision; takeaways/outline whose evidence
  changed are marked "source changed — review again".
- **Languages:** transcription locale picker from `SpeechTranscriber.supportedLocales`; insights generated
  in the transcript's language when the model supports it.
- **Venue suggestion:** one-shot foreground location → nearby churches via `MKLocalSearch` → listener picks
  or types; precision choice (church / city / private). Never stored precisely.
- **Service QR codes:** scan (camera UI is Claude's; decode/verify is core) a church-signed token
  `{church, service, startsAt, recordingAllowed, publicSharingAllowed, reviewRequired, expiresAt}` verified
  against the server's published church signing keys (cached; offline-verifiable).

### 2. Identity and accounts
- Device key (P-256, Keychain; Secure Enclave when available) → `POST /v1/accounts` → account id. Requests
  are signed (method, path, timestamp, body SHA-256); server verifies with WebCrypto; ±5 min skew; nonce
  replay protection.
- Optional display name and avatar style (no photos). Private by default.
- **Recovery kit:** passphrase-wrapped private key (PBKDF2/HKDF + AES-GCM) exported as a file/QR; restore
  on another device. Delete account (server data removed; local data kept unless erased).
- Roles: listener, church staff (per church), moderator, admin. Web consoles use short-lived codes issued to
  a signed-in app account ("Link a browser" shows a code) or an admin bootstrap secret; sessions are
  HttpOnly SameSite=Strict cookies.

### 3. Publishing (explicit, reviewed)
Flow in the app: choose what to share (card metadata only / + reviewed big idea & reflection / + trimmed
enhanced audio) → sensitive-content checklist (music, prayer requests, children, private talk) → rights
basis (service QR, church will review, none = metadata only) → confirm → background upload.
Server states: `pendingUpload → uploading → quarantine → validating → pendingRights → approved → published`
plus `rejected | disputed | removed | superseded`. Validation: size ≤ 200 MB, `ftyp` m4a/AAC, duration
claim ≤ 3 h and consistent with size, checksum match. Audio stays in a private R2 prefix until approved.
**Canonical matching:** same church ±1 day and similar title/passage → attach to existing canonical sermon
(contributor credit), else create one. Transcripts are never uploaded.

### 4. Community discovery and listening
- Discover feed: recent published sermons, filters (type, theme, church, city, passage, verified only),
  search. Church pages (verified churches, their sermons). Sermon page for community sermons.
- Authorized playback via short-lived signed URLs; rights re-checked at issue time; disputed/removed audio
  shows the unavailable state while the card and history remain.
- Keeping a community sermon adds it to the library (source: discover/pack/trade/shared) and mints a card.

### 5. Cards and trading
- Server mints Card Instances for community sermons (edition: Community, or Church when official audio),
  per-edition serials. Private-only sermons keep local Personal cards (not tradeable until published as a
  community card).
- **Offers:** gift or swap. Create → offer token → QR, share link, or **nearby** (MultipeerConnectivity
  carries the token). Recipient reviews (card preview, sender's display name, optional note) → accept /
  decline / propose a swap card → sender confirms. Server performs atomic transfer with version checks and
  idempotency keys; offers expire (default 7 days) and can be cancelled. Both libraries keep the sermon.
- **Blocking:** blocked accounts can't send offers or see your display name.
- Trade history per card (coarse journey stops when opted in).

### 6. Sunday Pack (real)
Weekly cron builds a curated pool from published sermons (diverse churches/themes, current liturgical
season tag, local + wider). Each account gets a deterministic 5-card pack per ISO week, excluding sermons
already in its library; opening mints the cards. Free, one per week, no odds shown or implied.
Fallback to bundled samples when offline or the pool is small (clearly labelled).

### 7. Atlas
- Personal layer (done): where your library's sermons were preached.
- **Community layer:** counts of published sermons per city/church (public venues only).
- **Card Journeys (opt-in):** ordered coarse city stops for a card instance; shown only when every
  participant opted in; hide-past-events control; cohort suppression (< 3 distinct cards per city).

### 8. Trust, rights, safety
- Trust labels (Personal draft, Community matched, Church verified, Audio authorized, Official audio,
  Disputed, Audio removed) computed server-side for community sermons.
- **Reports** with reason and optional timestamp (rights, privacy, wrong attribution, misleading edit,
  sensitive content, abuse/impersonation) on sermons, audio, cards, accounts.
- **Moderation console (web):** queues (uploads pending rights, reports, church claims), actions (approve,
  reject, dispute, remove audio, restore, ban, unban), notes, full audit log, appeals.
- **Church portal (web):** claim a church (evidence: website, role; moderator verifies), manage church
  profile and public location, claim/correct sermons, approve/reject listener recordings, upload official
  audio (becomes canonical; listeners choose whether to switch, with the "your moments may shift" warning),
  request immediate removal, issue service QR codes (print view), credit policy for contributors.

### 9. Backup, export, sync
- **Backup to Files:** archive (zip) of the whole library including audio, notes, moments, transcripts →
  `fileExporter` (iCloud Drive, Google Drive, Dropbox via their Files providers). **Restore** merges
  without duplicates. Optional passphrase encryption. iPhone backup inclusion stays the default.
- **Account sync:** only server-side community state (owned cards, community library entries, offers,
  inbox). Personal content is never synced.
- JSON export (done).

### 10. Inbox and sharing
- In-app inbox: trade offers, offer results, publication status changes, church decisions, moderation
  outcomes. Polled on foreground and pull-to-refresh.
- Share a card: rendered card image (Claude) + optional share link `https://<domain>/s/<id>` (server
  stores the uploaded card image and public sermon metadata) whose page (Claude's HTML) shows the card,
  summary, Listen (if authorized), and Open in app.

### 11. Polish and quality bar
Every screen in all four looks, Dynamic Type through AX5, VoiceOver labels, Reduce Motion, empty / error /
offline states with plain-language recovery, no dead ends. Unit tests for every invariant; UI journeys for
every primary flow; local server integration tests; documented physical-device checklist.
