# Community API

API-VERSION: 1

This contract is authoritative for the Worker, native client, and web consoles. Base URL is
`PUBLIC_BASE_URL`; local development is `http://127.0.0.1:8787`. JSON uses camelCase, opaque string
IDs, UTC ISO-8601 dates, integer ownership versions, seconds for audio positions, and lowercase
hex SHA-256. No endpoint accepts personal notes, moments, transcripts, private originals, precise
listener coordinates, playback history, AI drafts, or arbitrary extra fields. Published `summary`
and `reflectionPrompt` are separately reviewed public copy. Offer `message` is an explicit message
to the recipient (not a private note). Unknown JSON fields are rejected.

## Transport, identity, and errors

All JSON responses include `API-Version: 1`. Error response:
`{"error":{"code":"invalid_request","message":"Readable recovery guidance"}}`.
Codes: `invalid_request` (400), `unauthorized` / `invalid_signature` / `replay` (401),
`forbidden` / `blocked` (403), `not_found` (404), `conflict` / `stale_version` /
`idempotency_conflict` (409), `expired` / `audio_unavailable` (410), `too_large` (413),
`invalid_audio` (422), `not_configured` (503), `internal_error` (500). Errors never echo content.

Auth column: **public** needs no account; **signed** needs the following headers; **account** accepts
signed auth or a web session; **staff** additionally requires an active role for the route's church;
**moderator** accepts moderator/admin; **admin** requires admin. A banned account cannot mutate or
listen through authenticated APIs. Public discovery contains no account display names.

Signed requests have `X-Account-ID`, `X-Timestamp` (Unix seconds, decimal), `X-Nonce` (random UUID),
`X-Signature` (base64url, unpadded, 64-byte IEEE P1363 r||s P-256 ECDSA/SHA-256 signature).
Canonical UTF-8 input, with exactly these newline-separated lines and no final newline:

```text
v1
UPPERCASE_METHOD
/path?exact=query&in=wire-order
account-id
unix-seconds
nonce
lowercase-sha256-of-exact-body-bytes
```

GET and bodyless requests hash empty bytes. Query order and encoding are signed. Server verifies
P-256 WebCrypto signatures, permits ±300 seconds, and consumes a nonce atomically only after valid
verification. Nonces are retained ≥10 minutes. Retrying uses a NEW nonce and the SAME
`Idempotency-Key`. Registration uses an empty account-id line, omits `X-Account-ID`, and signs with
the submitted public key. A unique public key maps to one account; recovery restores that identity.
DER signatures from Apple's APIs must be converted to P1363 by the client.

Every JSON POST/PATCH/DELETE mutation except session creation/logout requires `Idempotency-Key` (UUID or
16–128 printable token characters). Scoped to account + key; same method/path/body returns the
original JSON result, different bytes return 409. Failed transactions consume no idempotency key.
Upload PUTs are immutable and retryable by checksum; do not require an idempotency header.
Registration retries return the account for that key. Delete retries after deletion return 401;
clients treat deletion completion as success and erase the remote identity locally if desired.

List responses: `{"items":[T],"nextCursor":string|null}`. `limit` defaults 20, maximum 100;
`cursor` is an opaque base64url offset. Sync is a complete paginated snapshot, not a private-library
backup. GET arrays are stable for an unchanged dataset; concurrent additions can require refresh.

## Shared shapes (all fields required unless marked ?)

```typescript
type PublicKey = {kty:"EC"; crv:"P-256"; x:string; y:string; ext?:boolean; key_ops?:string[]};
type Account = {id:string; displayName:string|null; avatarStyle:string; journeyOptIn:boolean;
  journeyCity:string|null; creditOptIn:boolean; roles:{role:"listener"|"churchStaff"|"moderator"|"admin";churchID:string|null}[]};
type Church = {id:string; name:string; city:string|null; region:string|null; country:string|null;
  website:string|null; verified:boolean; creditPolicy:"named"|"anonymous"; fictional:boolean};
type Sermon = {id:string; churchID:string|null; title:string; preacher:string; service:string|null;
  serviceDate:string; primaryPassage:string; themes:string[]; sermonType:string;
  city:string|null; region:string|null; country:string|null; summary:string|null;
  reflectionPrompt:string|null; state:string; trustLabels:string[]; audioAvailable:boolean;
  canonicalAudioAssetID:string|null; fictional:boolean; createdAt:string};
type Card = {id:string; sermonID:string; editionID:string; edition:"Community"|"Church";
  serialNumber:number; ownerID:string; version:number; tradeable:boolean; createdAt:string};
type History = {sermonID:string; source:"discover"|"pack"|"trade"|"shared";
  firstEncounteredAt:string};
type Publication = {id:string; sermonID:string; state:PublicationState; audioAssetID:string|null;
  createdAt:string; review?:PublicationReview};
type PublicationReview = {title:string;preacher:string;serviceDate:string;primaryPassage:string;
 sermonType:string;themes:string[];summary:string|null;reflectionPrompt:string|null;rightsBasis:string;
 checklist:{musicReviewed:boolean;prayerRequestsReviewed:boolean;childrenReviewed:boolean;privateTalkReviewed:boolean}|null;
 audio:{duration:number;byteCount:number}|null;contributorDisplayName:string|null};
type PublicationState = "pendingUpload"|"uploading"|"quarantine"|"validating"|"pendingRights"|
  "approved"|"published"|"rejected"|"disputed"|"removed"|"superseded";
type Offer = {id:string; kind:"gift"|"swap"; senderID:string; recipientID:string|null;
  cardID:string; cardVersion:number; proposedCardID:string|null; proposedCardVersion:number|null;
  message:string|null; state:"open"|"proposed"|"accepted"|"declined"|"cancelled"|"expired";
  expiresAt:string; createdAt:string};
type Receipt = {ok:true; [namedResourceID:string]:string|boolean};
```

The owning account sees its profile; another account's display name is returned only in an authorized
offer preview and is null across a block. No public account directory exists. Trust labels are
computed from server state: `Community matched`, `Church verified`, `Audio authorized`,
`Official audio`, `Disputed`, `Audio removed`. They never assert endorsement.

## Identity, web sessions, sync, and blocking

| Method/path | Auth | Request → response |
|---|---|---|
| GET `/health` | public | → `{ok:true,apiVersion:1}` |
| POST `/v1/accounts` | registration signature | `{publicKey:PublicKey,displayName?:string,avatarStyle?:string}` → `{account:Account}` |
| GET `/v1/me` | account | → `{account:Account}` |
| PATCH `/v1/me` | account | `{displayName?:string|null,avatarStyle?:string,journeyOptIn?:boolean,journeyCity?:string|null,hidePastJourneys?:boolean,creditOptIn?:boolean}` → `{ok:true,accountID:string}` |
| DELETE `/v1/me` | account | empty body → `{ok:true}`; delete associated state/media, preserve other owners' public collection references with anonymous credit |
| POST `/v1/web/link-codes` | signed | `{}` → `{code:string,expiresAt:string}`; single-use, 5 minutes |
| POST `/v1/web/session` | public | `{code:string}` OR `{bootstrapSecret:string,accountID:string}` → `{account:Account,csrfToken:string,expiresAt:string}` + cookie; bootstrap assigns admin to an existing account |
| GET `/v1/web/session` | account | → `{account:Account,csrfToken:string,expiresAt:string|null}` |
| DELETE `/v1/web/session` | account | empty → `{ok:true}` + expired cookie |
| POST `/v1/blocks` | account | `{accountID:string}` → `{ok:true}` |
| DELETE `/v1/blocks/:accountID` | account | empty → `{ok:true}` |
| GET `/v1/blocks` | account | → page of `{accountID:string}` |
| GET `/v1/library` | account | → page of History |
| GET `/v1/cards` | account | → page of Card |
| GET `/v1/cards/:id/history` | account owner/former participant | → page of `{version:number,kind:"minted"|"transferred",occurredAt:string}`; ownership ledger omits other identities and places |
| GET `/v1/offers` | account | → page of Offer involving account |
| GET `/v1/inbox` | account | → page of `{id:string,type:string,resourceID:string,createdAt:string,read:boolean}` |
| POST `/v1/inbox/:id/read` | account | `{}` → `{ok:true}` |

Recovery is client-only: a passphrase-wrapped private key restores access via signed `GET /v1/me`.
The server stores no passphrase, recovery kit, private key, or private backup. Account ID and public
key should be included in the kit. A recovered key can re-register to resolve its existing account ID.

Cookie is `community_session`, Secure on HTTPS, HttpOnly, SameSite=Strict, Path=/, TTL 8 hours.
Every cookie-authenticated write needs exact same-origin `Origin` AND `X-CSRF-Token` from session
exchange; signed requests do not need CSRF. No CORS cross-origin write access. Bootstrap secret is
only a Worker secret, never a variable, URL parameter, or static file. Login codes are hashed at rest.

## Publishing and audio

```typescript
type PublishRequest = {title:string; preacher:string; churchID?:string|null; service?:string|null;
 serviceDate:string; primaryPassage:string; themes:string[]; sermonType:string;
 city?:string|null; region?:string|null; country?:string|null; summary?:string|null;
 reflectionPrompt?:string|null; reviewed:boolean;
 checklist:{musicReviewed:boolean;prayerRequestsReviewed:boolean;childrenReviewed:boolean;
 privateTalkReviewed:boolean}; rightsBasis:"none"|"churchReview"|"serviceQR"|"official";
 serviceToken?:string; audio?:{byteCount:number;duration:number;checksumSHA256:string;
 contentType:"audio/mp4";trimStart:number;trimEnd:number;sourceChecksumSHA256:string}};
```

| Method/path | Auth | Request → response |
|---|---|---|
| POST `/v1/publications` | account | PublishRequest → `{publicationID:string,sermonID:string,audioAssetID:string|null,uploadURL:string|null}` |
| GET `/v1/publications` | account | → page of own Publication |
| GET `/v1/publications/:id` | account (owner/staff/mod) | → `{publication:Publication}` |
| PUT `/v1/uploads/:assetID?token=…` | upload capability | raw M4A bytes, `Content-Type: audio/mp4` → `{ok:true}` |
| POST `/v1/publications/:id/complete` | account owner | `{}` → `{ok:true,publicationID:string}`; validate and move to pendingRights or publish with verified QR/official grant |
| POST `/v1/sermons/:id/audio-url` | account | `{}` → `{url:string,expiresAt:string,audioAssetID:string,alignmentWarning:string|null}` |
| GET/HEAD `/v1/audio/:assetID?expires=unix&signature=base64url` | audio capability | `audio/mp4`, supports single byte `Range`; rights rechecked again on redemption |
| GET `/v1/sermons/:id/contributors` | public | → page of `{displayName:string|null}` only when account creditOptIn AND church named policy permit it (blocked names hidden) |

Uploads are single-asset HMAC capabilities expiring after 24 hours; authorize only immutable objects
under `private/audio/:assetID`. No public R2 bucket. SHA-256 + byte count + AAC M4A `ftyp`, audio
sample entry and container duration are verified; maximum 200,000,000 bytes, 10,800 seconds, trim
window matches supplied duration. Original checksum is provenance only; originals never uploaded.
No transcoding or server AI. `rightsBasis:none` forbids audio, but allows reviewed metadata.
`official` requires verified church staff. QR must match church, service and date, permit public
sharing, and remain unrevoked/unexpired. `reviewRequired:true` sends to church review.

Canonical matching: same church, service date ±1 day, normalized title OR passage similarity;
contributions attach to an existing sermon and receive credit without replacing its metadata/audio.
Official approved audio supersedes the old asset and changes only the canonical pointer; old cards
and history remain. Audio URL returns `alignmentWarning:"Your moments may shift."` for official audio;
clients choose whether to switch and retain their original marker source. Metadata-only publishing
never implies authorized audio.

Publication transitions:
`pendingUpload → uploading → quarantine → validating → pendingRights → approved → published`.
Metadata-only starts `pendingRights`. Verified non-review QR and official staff complete approval
and publication after validation. Review approve publishes, reject rejects; published can become
`disputed` or `removed`, restored only with a still-valid grant; replacement becomes `superseded`.
Every transition is validated. Inbox records changes. `approved` is a transaction-internal state.
Audio issue/redemption requires published asset + active grant + available canonical sermon.
Signed audio signature is base64url HMAC-SHA256 of `audio\nassetID\nexpires`, TTL 5 minutes.

## Discovery, keep, packs, Atlas, journeys

| Method/path | Auth | Request → response |
|---|---|---|
| GET `/v1/discover` | public | query `q,type,theme,churchID,city,passage,verified` + pagination → page of Sermon |
| GET `/v1/sermons/:id` | public | → `{sermon:Sermon}` (removed/disputed retain metadata/history) |
| GET `/v1/churches` | public | query `q,verified` + pagination → page of Church |
| GET `/v1/churches/:id` | public | → `{church:Church}` |
| GET `/v1/churches/:id/sermons` | public | → page of published Sermon |
| POST `/v1/sermons/:id/keep` | account | `{source:"discover"|"shared"}` → `{ok:true,cardID:string}`; at most one keep card per account/sermon, independent of later trades |
| GET `/v1/packs/current` | account | → `{week:string,season:string,sermonIDs:string[],opened:boolean,fallback:boolean}`; deterministic 5 distinct unowned sermons when available; smaller pool labelled fallback |
| POST `/v1/packs/:week/open` | account | `{}` → `{ok:true,week:string}`; one atomic mint per account/current ISO week; cards in `/v1/cards`, history in `/v1/library` |
| GET `/v1/atlas` | public | → `{places:{churchID:string|null,city:string|null,region:string|null,country:string|null,count:number}[]}`; only published public places |
| GET `/v1/cards/:id/journey` | public | → `{cardID:string,stops:{city:string,week:string}[],suppressed:boolean}`; empty unless every participant currently opted in, every event visible, and each city has ≥3 distinct consenting cards |

Pack selection is frozen before opening, seeded by account/week, excludes all library sermons;
Sunday cron builds diverse church/theme pools with a season tag. Client bundled offline fallback
stays local and is labelled sample. Server does not reissue cards for repeated opens/keeps.
Journeys store only coarse city names, expose ISO weeks, no participant IDs or exact times;
opt-out/hide-past hides the entire affected trace, and cohorts count eligible traces only.

## Offers

| Method/path | Auth | Request → response |
|---|---|---|
| POST `/v1/offers` | account | `{kind:"gift"|"swap",cardID:string,cardVersion:number,recipientID?:string|null,message?:string|null,expiresAt?:string}` → `{offerID:string,token:string}` |
| GET `/v1/offers/:id?token=…` | account | → `{offer:Offer,card:Card,senderDisplayName:string|null}`; sender, bound recipient, or bearer token; block enforced |
| POST `/v1/offers/:id/accept` | account | `{token?:string}` → `{ok:true,offerID:string}`; gifts only, bind recipient atomically |
| POST `/v1/offers/:id/propose` | account | `{token?:string,cardID:string,cardVersion:number}` → `{ok:true,offerID:string}`; bind recipient, await sender |
| POST `/v1/offers/:id/confirm` | account sender | `{}` → `{ok:true,offerID:string}`; swap both cards atomically |
| POST `/v1/offers/:id/decline` | account recipient/token | `{token?:string}` → `{ok:true,offerID:string}` |
| POST `/v1/offers/:id/cancel` | account sender | `{}` → `{ok:true,offerID:string}` |

`open → accepted` (gift), `open → proposed → accepted` (swap). `open/proposed →
declined/cancelled/expired` changes no ownership. Default expiry 7 days, max 7 days; checked on every
transition and hourly cron. Card version CAS is validated inside the same D1 transaction as both
ownership changes, new library history, journey events, inbox results, and idempotency receipt.
Competing offers can exist, but only one can consume a given version. A block prevents token preview,
proposal or transfer in either direction and cancels pending offers between the two accounts.

## Offline-verifiable tokens and published keys

GET `/v1/keys` (public) → `{keys:[{kid:string,alg:"ES256",publicKey:PublicKey}]}`.
Tokens use compact JWS `base64url(header).base64url(payload).base64url(signature)` (no padding).
Header is `{alg:"ES256",kid:string,typ:"offer+jwt"|"service+jwt"}`; signature is P1363 P-256
SHA-256 of ASCII `header.payload`. Cache keys by kid; reject unknown alg/kid, wrong typ, invalid
signature, wrong version/audience, or expired tokens. No sensitive/private data in tokens.

Offer payload: `{v:1,aud:PUBLIC_BASE_URL,offerID:string,cardID:string,senderID:string,exp:number}`.
Service payload: `{v:1,aud:PUBLIC_BASE_URL,id:string,church:string,service:string,startsAt:string,
recordingAllowed:boolean,publicSharingAllowed:boolean,reviewRequired:boolean,expiresAt:string,
exp:number}`. The service QR is contextual evidence, not blanket clearance. Offline verification
cannot learn revocation; uploads always check the current server record. Keep retired public keys
published until their tokens expire. Signing private JWK and published-key array are Worker secrets
`TOKEN_SIGNING_JWK` and `TOKEN_PUBLIC_KEYS`; active key id is `TOKEN_KEY_ID`.

## Reports, moderation, appeals, church portal

| Method/path | Auth | Request → response |
|---|---|---|
| POST `/v1/reports` | account | `{targetType:"sermon"|"audio"|"card"|"account",targetID:string,reason:"rights"|"privacy"|"wrongAttribution"|"misleadingEdit"|"sensitiveContent"|"abuse",timestamp?:number,details?:string}` → `{ok:true,reportID:string}` |
| GET `/v1/moderation/queue` | moderator | query `kind=reports|publications|claims|appeals|removals` → page of queue objects (see below) |
| POST `/v1/moderation/actions` | moderator | `{targetType:"publication"|"sermon"|"audio"|"account"|"claim"|"report"|"appeal",targetID:string,action:"approve"|"reject"|"dispute"|"remove"|"restore"|"ban"|"unban"|"resolve",reason:string}` → `{ok:true,actionID:string}`; account ban/unban admin-only; grants checked on restore |
| GET `/v1/moderation/audit` | moderator | → page of `{id:string,actorID:string|null,targetType:string,targetID:string,action:string,reason:string,createdAt:string}` |
| POST `/v1/appeals` | account | `{actionID:string,reason:string}` → `{ok:true,appealID:string}`; affected account only |
| GET `/v1/appeals` | account | → page of own appeals |
| POST `/v1/church-claims` | account | `{churchID?:string,name:string,website:string,role:string,evidence:string}` → `{ok:true,claimID:string}`; moderator approve verifies church and grants churchStaff role |
| GET `/v1/portal/churches` | account | → page of Church manageable by account |
| PATCH `/v1/portal/churches/:id` | staff | `{name?:string,city?:string|null,region?:string|null,country?:string|null,website?:string,creditPolicy?:"named"|"anonymous"}` → `{ok:true,churchID:string}` |
| GET `/v1/portal/churches/:id/publications` | staff | → page of Publication for church |
| POST `/v1/portal/churches/:id/sermons/:sermonID/claim` | staff | `{reason:string}` → `{ok:true,sermonID:string}`; assigns unclaimed sermons only, cross-church disputes require moderator |
| POST `/v1/moderation/sermons/:id/correct` | moderator | `{churchID?:string|null,title?:string,preacher?:string,primaryPassage?:string,serviceDate?:string,reason:string}` → `{ok:true,sermonID:string}`; attribution changes disable audio whose grant covers the previous church |
| POST `/v1/portal/churches/:id/sermons/:sermonID/correct` | staff | `{title?:string,preacher?:string,primaryPassage?:string,serviceDate?:string}` → `{ok:true,sermonID:string}`; claims verified attribution |
| POST `/v1/portal/churches/:id/publications/:pubID/preview-url` | staff | `{}` → `{url:string,expiresAt:string}`; protected reviewer audio |
| POST `/v1/moderation/publications/:pubID/preview-url` | moderator | `{}` → `{url:string,expiresAt:string}`; protected reviewer audio |
| GET/HEAD `/v1/review-audio/:assetID?token=…` | account + staff/moderator | requires the issuing reviewer identity/session AND 5-minute HMAC token, supports Range; never an anonymous media capability |
| POST `/v1/portal/churches/:id/publications/:pubID/decision` | staff | `{decision:"approve"|"reject",reason:string}` → `{ok:true,publicationID:string}`; approval creates scoped church grant |
| POST `/v1/portal/churches/:id/official-audio` | staff | PublishRequest (churchID must match; rightsBasis official) → same result as POST publications |
| POST `/v1/portal/churches/:id/removals` | staff | `{sermonID:string,reason:string}` → `{ok:true,requestID:string}`; immediately disables audio, logs request/audit |
| POST `/v1/portal/churches/:id/services` | staff | `{service:string,startsAt:string,recordingAllowed:boolean,publicSharingAllowed:boolean,reviewRequired:boolean,expiresAt:string}` → `{serviceID:string,token:string,printURL:string}` |
| GET `/v1/portal/churches/:id/services` | staff | → page of `{id:string,service:string,startsAt:string,expiresAt:string,recordingAllowed:boolean,publicSharingAllowed:boolean,reviewRequired:boolean,revoked:boolean,token:string}` |
| POST `/v1/portal/churches/:id/services/:serviceID/revoke` | staff | `{}` → `{ok:true}`; revokes dependent audio access immediately |

Queue `reports`: `{id,reporterID,targetType,targetID,reason,timestamp:number|null,details:string|null,targetSummary:string,state,createdAt}`;
`publications`: Publication with required `review:PublicationReview`; `claims`: `{id,accountID,churchID:string|null,name,website,role,evidence,state,createdAt}`;
`appeals`: `{id,accountID,actionID,reason,state,createdAt}`;
`removals`: `{id,churchID,sermonID,accountID,reason,createdAt}` (all unannotated fields strings).
Console data is role-restricted and never contains raw transcripts or private listener material.

## Sharing and web contract

| Method/path | Auth | Request → response |
|---|---|---|
| POST `/v1/shares` | account | `{sermonID:string,byteCount:number,checksumSHA256:string}` → `{shareID:string,uploadURL:string,url:string}` |
| PUT `/v1/share-images/:id?token=…` | image capability | PNG bytes ≤10 MB, verified PNG signature/checksum → `{ok:true}` |
| GET `/v1/shares/:id` | public | → `{id:string,sermon:Sermon,imageURL:string,url:string,appURL:string}` |
| GET `/v1/share-images/:id` | public | verified `image/png` (metadata-only public card, never private captures) |
| GET `/s/:id` | public | server-rendered share template |
| GET `/portal/services/:id/print` | staff | server-rendered service print template |

Static assets binding `ASSETS` points to `../web`. Worker handles `/v1/*`, `/health`, `/s/*`, and
`/portal/services/*/print` first. Everything else forwards to `ASSETS`, including `/`, `/portal`,
`/moderation`, CSS/JS/images, `brand.json`; Claude should supply `index.html`, `portal/index.html`,
`moderation/index.html` and assets. Owner-facing routes `/church` and `/moderate` serve `/portal/` and `/moderation/` static shells; old paths remain aliases. `GET /t/:token` serves `web/t/index.html` through `/t/` without passing the token to that asset request, with no-store/no-referrer. The static page reads the token from its own browser pathname and links to `BRAND_SCHEME://offer/:token`. Static console shells may be public; APIs enforce roles.

Claude's templates are `web/templates/share.html` and `web/templates/service-print.html`, fetched
through ASSETS and interpolated by the Worker. Exact placeholders use `{{name}}`; all substitutions
are HTML-escaped, including URLs. Templates may not rely on executable unescaped JSON.

Share variables: `brandName`, `title`, `preacher`, `passage`, `churchName`, `city`, `summary`,
`reflectionPrompt`, `imageURL`, `shareURL`, `appURL`, `sermonID`, `audioStatus`, `fictionalLabel`.
Listen links should target `appURL`: authenticated audio is issued by the app; `audioStatus` is
`Audio available` or `Audio unavailable`. No public permanent audio URL in HTML. `appURL` is
`BRAND_SCHEME://sermon/:sermonID`. Rendered pages carry a restrictive CSP and no analytics.

Print variables: `brandName`, `churchName`, `service`, `startsAt`, `expiresAt`, `recordingAllowed`,
`publicSharingAllowed`, `reviewRequired`, `token`, `qrValue`, `serviceID`.
`qrValue` is the compact signed service token; Claude's local QR renderer uses this value, never an
external QR service. Boolean variables are `Yes`/`No`. Template absence has an accessible minimal
server fallback page using the same variables, visibly labelled without a fake QR.

## Changelog

- 2026-10-05: Initial API-VERSION 1 contract published before backend implementation. Full endpoint,
  signing, privacy, role, token, web-template and state-machine contracts.
- 2026-10-05: Browser logout also permits omission of Idempotency-Key; CSRF and same-origin checks
  still apply. This supports the console's session-only sign-out flow.

- 2026-10-05: Applied the owner’s Sower brand and `/church`, `/moderate`, `/t/:token` routes. Added review objects to church/moderator publication lists, report targetSummary, and authenticated five-minute reviewer-audio preview endpoints requested in WEB-REQUESTS.md. These are additive API v1 changes.

- 2026-10-05: Added default-off creditOptIn, a participant-only card ownership-history endpoint, audited unclaimed-sermon claiming and moderator attribution corrections. Church reassignment withdraws previous audio access; fresh verified official audio can replace a removed/disputed canonical asset without moving cards or history.
