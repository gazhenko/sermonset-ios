# API requests from the web consoles (Claude → Codex server)

1. **Pending publication details for reviewers.** Church staff (`/v1/portal/churches/:id/publications`) and
   moderators (`/v1/moderation/queue?kind=publications`) see only `{id, sermonID, state, audioAssetID,
   createdAt}`; unpublished sermons 404 on `GET /v1/sermons/:id`. Please include a `review` object on
   these rows: `{title, preacher, serviceDate, primaryPassage, sermonType, themes, summary,
   reflectionPrompt, rightsBasis, checklist, audio: {duration, byteCount} | null, contributorDisplayName}`.
2. **Reviewer audio preview.** `POST /v1/portal/churches/:id/publications/:pubID/preview-url` (staff) and
   `POST /v1/moderation/publications/:pubID/preview-url` (moderator) → `{url, expiresAt}`: a short-lived
   signed URL for the quarantined/pending asset so reviewers can listen before approving. Never public.
3. **Report targets.** Moderation report rows: include `{targetSummary}` (sermon title / card serial / "Account")
   so the console can show what was reported without extra lookups.

## Offer links (from Claude, UI)

The app shares offers as `https://sower.gazhenko.dev/t/<token>` (the QR in the app uses `sower://offer/<token>`).
Please route `GET /t/<anything>` to the static page `web/t/index.html` (e.g.
`env.ASSETS.fetch(new Request(new URL('/t/', url), request))`), with `Cache-Control: no-store` and
`Referrer-Policy: no-referrer`. The page reads the token from `location.pathname` client-side and offers an
"Open in Sower" button (`sower://offer/<token>`); it never sends the token anywhere.

## Local dev: strip production routes (from Claude, found in console testing)

`scripts/dev.mjs` copies `routes = [{ pattern = "sower.gazhenko.dev", custom_domain = true }]` into
`.tmp/wrangler.local.toml`. With it, `wrangler dev` rewrites the request's Origin, so every
`POST /v1/web/session` locally fails the same-origin check with 403 ("Open the console on its configured
origin") even when the browser is on http://127.0.0.1:8787. Please drop `routes` (and `workers_dev`) from the
derived local config, and add a test that a same-origin console sign-in succeeds through the dev wrapper.

## Don't notify people about their own actions (from Claude, found in UI review)

`offers.ts` `transition()` writes an inbox event to both the sender and the recipient for every non-accept
transition. When the sender cancels, the sender gets "An offer was cancelled" about their own tap; same for a
recipient's own decline. Please skip the event for the account performing the action (still notify the other
party), and add a test.

## Production D1 rejects the trigger migrations (from Claude, blocking deploy)

`wrangler d1 migrations apply DB --remote` against the new production database fails on 0001 with
`incomplete input: SQLITE_ERROR [code: 7500]`. Remote D1 splits migration files into statements and treats the
inner `... THEN RAISE(ABORT,'x') END;` lines inside `CREATE TRIGGER ... BEGIN ... END;` as statement ends;
Miniflare accepted them locally. Nothing has been applied in production yet (only `d1_migrations` exists), so
0001 may be rewritten. Please rewrite every trigger body (0001 and the new 0004) so no line inside a trigger ends
with `END;` except the trigger's own end, e.g. `SELECT RAISE(ABORT,'expired') WHERE julianday(OLD.expires_at)<=julianday('now');`,
keeping identical behavior. Add a test that splits each migration the way D1 does (statements end at `;` that is
not inside a string, and only `END;` at line start closes a trigger) or otherwise proves no inner `END;` remains,
and keep all existing tests green. Claude will verify against a throwaway remote D1 database.
