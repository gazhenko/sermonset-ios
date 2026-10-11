# Production deployment

SOWER's community server runs on the owner's Cloudflare account (free tier) at
`https://sower.gazhenko.dev`. The marketing site is GitHub Pages at
`https://gazhenko.dev/sower/`, built from `site/` and published to the `gh-pages` branch with
`tools/site/publish.sh`.

## Cloudflare resources

| Resource | Name | Notes |
| --- | --- | --- |
| Worker | `sower` | Custom domain `sower.gazhenko.dev`; static files from `web/` |
| D1 | `sower-db` | ID in `server/wrangler.toml`; schema from `server/migrations/` only, never seeded |
| R2 | `sower-audio` | Private. Shared audio and staging uploads |
| R2 | `sower-images` | Private. Share-card images, served through the Worker |

## Secrets

Generated fresh for production (never the local `.dev.vars` fixtures) and uploaded with
`wrangler deploy --secrets-file` from a 0600 temporary file that is deleted afterwards. A backup of each
value is in the owner's login Keychain under the service **sower-production**:

- `TOKEN_SIGNING_JWK` — private P-256 key that signs service and offer QR tokens (kid `community-p256-v1`).
- `TOKEN_PUBLIC_KEYS` — the published key list served at `/v1/keys`.
- `CAPABILITY_SECRET` — HMAC secret for short-lived audio and upload links.
- `ADMIN_BOOTSTRAP_SECRET` — one-time admin setup. After the first admin signs in, delete it:
  `wrangler secret delete ADMIN_BOOTSTRAP_SECRET` (and the Keychain item).

Read one back with `security find-generic-password -s sower-production -a <NAME> -w`.

## Commands (from `server/`, with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` set)

```sh
./node_modules/.bin/wrangler d1 migrations apply DB --remote
./node_modules/.bin/wrangler deploy --secrets-file <0600 json>
```

The API token needs Workers Scripts edit, D1 edit, R2 edit, and the gazhenko.dev zone's Workers routes.

## First admin

1. In the app (pointed at production), create a community account and copy Settings › Community › your name ›
   Account ID.
2. Open `https://sower.gazhenko.dev/moderate`, choose First-time setup, paste the account ID and the
   `ADMIN_BOOTSTRAP_SECRET` from the Keychain.
3. Delete the bootstrap secret as above.
