import type { Context, Env, Row } from "./types";
import {
  APIError,
  command,
  event,
  fail,
  fields,
  json,
  noBody,
  one,
  page,
  replay,
  rows,
  sha,
  sql,
  str,
  uid,
} from "./common";
import {
  authenticate,
  profile,
  register,
  requireRole,
  signingKeys,
} from "./security";
import {
  blockAccount,
  cleanupDeletedObjects,
  deleteAccount,
  linkCode,
  logout,
  updateProfile,
  webSession,
} from "./accounts";
import {
  audioURL,
  complete,
  listen,
  publish,
  publicationRow,
  previewURL,
  reviewListen,
} from "./publishing";
import { audioUpload, imageUpload } from "./media";
import {
  buildPool,
  getPack,
  journey,
  keep,
  openPack,
  packView,
  recomputeCohorts,
} from "./collection";
import { createOffer, expireOffers, preview, transition } from "./offers";
import {
  churchDecision,
  churchProfile,
  churchRemoval,
  correction,
  createAppeal,
  createClaim,
  createReport,
  issueService,
  moderationAction,
  queue,
  revokeService,
  serviceView,
  claimSermon,
  moderatorCorrection,
} from "./moderation";
import {
  appeal,
  audit,
  card,
  cardSelect,
  church,
  offer,
  publication,
  sermon,
  sermonSelect,
  reviewSelect,
  reviewedPublication,
} from "./projections";
import {
  createShare,
  printService,
  shareData,
  shareImage,
  sharePage,
} from "./web";

async function jsonBody(
  request: Request,
): Promise<{ bytes: Uint8Array; body: Row }> {
  const length = request.headers.get("content-length");
  if (length && Number(length) > 65536)
    fail(413, "too_large", "JSON payload exceeds the limit.");
  let bytes = new Uint8Array();
  if (request.body) {
    const reader = request.body.getReader();
    const chunks: Uint8Array[] = [];
    let count = 0;
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      count += item.value.length;
      if (count > 65536) {
        await reader.cancel();
        fail(413, "too_large", "JSON payload exceeds the limit.");
      }
      chunks.push(item.value);
    }
    bytes = new Uint8Array(count);
    let i = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, i);
      i += chunk.length;
    }
  }
  if (!bytes.length) return { bytes, body: {} };
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json")
    fail(400, "invalid_request", "Use application/json for this request.");
  try {
    const body = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!body || typeof body !== "object" || Array.isArray(body)) throw 0;
    return { bytes, body };
  } catch {
    fail(400, "invalid_request", "A valid JSON object is required.");
  }
}
async function publicRoute(
  request: Request,
  env: Env,
  url: URL,
): Promise<Response | null> {
  const path = url.pathname,
    method = request.method;
  let m: RegExpExecArray | null;
  if (method === "GET" && path === "/health")
    return json({ ok: true, apiVersion: 1 });
  if (
    ["GET", "HEAD"].includes(method) &&
    (/^\/t\/[^/]+$/.test(path) ||
      ["/church", "/church/", "/moderate", "/moderate/"].includes(path))
  ) {
    if (!env.ASSETS)
      fail(404, "not_found", "Static web files are not available yet.");
    const target = new URL(url);
    target.pathname = path.startsWith("/t/")
      ? "/t/"
      : path.startsWith("/church")
        ? "/portal/"
        : "/moderation/";
    target.search = "";
    const asset = await env.ASSETS.fetch(new Request(target, request));
    const response = new Response(asset.body, asset);
    response.headers.set("cache-control", "no-store");
    response.headers.set("referrer-policy", "no-referrer");
    return response;
  }
  if (method === "GET" && path === "/v1/keys")
    return json({ keys: await signingKeys(env) });
  if (
    ["GET", "HEAD"].includes(method) &&
    (m = /^\/v1\/audio\/([^/]+)$/.exec(path))
  )
    return listen(request, env, m[1], url);
  if (method === "PUT" && (m = /^\/v1\/uploads\/([^/]+)$/.exec(path)))
    return audioUpload(request, env, m[1], url);
  if (method === "PUT" && (m = /^\/v1\/share-images\/([^/]+)$/.exec(path)))
    return imageUpload(request, env, m[1], url);
  if (
    ["GET", "HEAD"].includes(method) &&
    (m = /^\/v1\/share-images\/([^/]+)$/.exec(path))
  )
    return shareImage(request, env, m[1]);
  if (method === "GET" && (m = /^\/v1\/shares\/([^/]+)$/.exec(path)))
    return json(await shareData(env, m[1]));
  if (method === "GET" && (m = /^\/s\/([^/]+)$/.exec(path)))
    return sharePage(env, m[1]);
  const c = { url, env };
  if (method === "GET" && path === "/v1/discover") {
    const where = ["s.state='published'"],
      args: unknown[] = [];
    for (const [name, column] of [
      ["type", "sermon_type"],
      ["churchID", "church_id"],
      ["city", "city"],
    ]) {
      const value = url.searchParams.get(name);
      if (value) {
        where.push(`s.${column}=?`);
        args.push(str(value, 200));
      }
    }
    for (const [name, column] of [
      ["passage", "primary_passage"],
      ["q", "title"],
    ]) {
      const value = url.searchParams.get(name);
      if (value) {
        where.push(
          name === "q"
            ? "(instr(lower(s.title),lower(?))>0 OR instr(lower(s.preacher),lower(?))>0 OR instr(lower(s.primary_passage),lower(?))>0)"
            : `instr(lower(s.${column}),lower(?))>0`,
        );
        const pattern = str(value, 200)!;
        args.push(pattern);
        if (name === "q") args.push(pattern, pattern);
      }
    }
    if (url.searchParams.get("theme")) {
      where.push(
        "EXISTS(SELECT 1 FROM json_each(s.themes) WHERE lower(value)=lower(?))",
      );
      args.push(str(url.searchParams.get("theme"), 60));
    }
    if (url.searchParams.get("verified") === "true")
      where.push("s.church_verified=1");
    return page(
      c,
      `${sermonSelect} WHERE ${where.join(" AND ")} ORDER BY s.created_at DESC,s.id`,
      args,
      sermon,
    );
  }
  if (method === "GET" && (m = /^\/v1\/sermons\/([^/]+)$/.exec(path)))
    return json({
      sermon: sermon(
        await one(
          env,
          `${sermonSelect} WHERE s.id=? AND s.state IN ('published','disputed','removed')`,
          m[1],
        ),
      ),
    });
  if (
    method === "GET" &&
    (m = /^\/v1\/sermons\/([^/]+)\/contributors$/.exec(path))
  ) {
    await one(
      env,
      "SELECT id FROM sermons WHERE id=? AND state IN ('published','disputed','removed')",
      m[1],
    );
    let viewer: string | null = null;
    if (request.headers.has("X-Account-ID") || request.headers.has("cookie"))
      viewer = (await authenticate(request, env, new Uint8Array())).account.id;
    return page(
      c,
      `SELECT CASE WHEN a.credit_opt_in=1 AND ch.credit_policy='named' AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.account_id=? AND b.blocked_id=a.id) OR (b.blocked_id=? AND b.account_id=a.id)) THEN a.display_name ELSE NULL END AS name FROM contributors co JOIN accounts a ON a.id=co.account_id JOIN sermons s ON s.id=co.sermon_id LEFT JOIN churches ch ON ch.id=s.church_id WHERE co.sermon_id=? ORDER BY co.account_id`,
      [viewer, viewer, m[1]],
      (r) => ({ displayName: r.name }),
    );
  }
  if (method === "GET" && path === "/v1/churches") {
    const where = ["1=1"],
      args: unknown[] = [];
    if (url.searchParams.get("verified") === "true") where.push("verified=1");
    if (url.searchParams.get("q")) {
      where.push("instr(lower(name),lower(?))>0");
      args.push(str(url.searchParams.get("q"), 150));
    }
    return page(
      c,
      `SELECT * FROM churches WHERE ${where.join(" AND ")} ORDER BY name,id`,
      args,
      church,
    );
  }
  if (method === "GET" && (m = /^\/v1\/churches\/([^/]+)$/.exec(path)))
    return json({
      church: church(await one(env, "SELECT * FROM churches WHERE id=?", m[1])),
    });
  if (method === "GET" && (m = /^\/v1\/churches\/([^/]+)\/sermons$/.exec(path)))
    return page(
      c,
      `${sermonSelect} WHERE s.church_id=? AND s.state='published' ORDER BY s.created_at DESC,s.id`,
      [m[1]],
      sermon,
    );
  if (method === "GET" && path === "/v1/atlas")
    return json({
      places: (
        await rows(
          env,
          "SELECT church_id,city,region,country,COUNT(*) AS count FROM sermons WHERE state='published' AND city IS NOT NULL GROUP BY church_id,city,region,country ORDER BY country,region,city,church_id",
        )
      ).map((r) => ({
        churchID: r.church_id,
        city: r.city,
        region: r.region,
        country: r.country,
        count: r.count,
      })),
    });
  if (method === "GET" && (m = /^\/v1\/cards\/([^/]+)\/journey$/.exec(path)))
    return json(await journey(env, m[1]));
  return null;
}
async function accountRoute(c: Context): Promise<Response> {
  const path = c.url.pathname,
    method = c.request.method;
  let m: RegExpExecArray | null;
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/sermons\/([^/]+)\/claim$/.exec(
      path,
    ))
  )
    return claimSermon(c, m[1], m[2]);
  if (
    method === "POST" &&
    (m = /^\/v1\/moderation\/sermons\/([^/]+)\/correct$/.exec(path))
  )
    return moderatorCorrection(c, m[1]);
  if (method === "GET" && (m = /^\/v1\/cards\/([^/]+)\/history$/.exec(path))) {
    const owned = await one(
      c.env,
      "SELECT owner_id FROM cards WHERE id=?",
      m[1],
    );
    if (
      owned.owner_id !== c.account.id &&
      !(await sql(
        c.env,
        "SELECT 1 FROM ownership_events WHERE card_id=? AND (from_account=? OR to_account=?)",
        m[1],
        c.account.id,
        c.account.id,
      ).first())
    )
      fail(403, "forbidden", "This history belongs to card participants.");
    return page(
      c,
      "SELECT version,kind,occurred_at FROM ownership_events WHERE card_id=? ORDER BY version",
      [m[1]],
      (r) => ({ version: r.version, kind: r.kind, occurredAt: r.occurred_at }),
    );
  }
  if (
    ["GET", "HEAD"].includes(method) &&
    (m = /^\/v1\/review-audio\/([^/]+)$/.exec(path))
  )
    return reviewListen(c, m[1]);
  if (
    method === "POST" &&
    (m = /^\/v1\/moderation\/publications\/([^/]+)\/preview-url$/.exec(path))
  )
    return previewURL(c, m[1]);
  if (
    method === "POST" &&
    (m =
      /^\/v1\/portal\/churches\/([^/]+)\/publications\/([^/]+)\/preview-url$/.exec(
        path,
      ))
  )
    return previewURL(c, m[2], m[1]);
  if (method === "GET" && path === "/v1/me")
    return json({ account: await profile(c.env, c.account) });
  if (method === "PATCH" && path === "/v1/me") return updateProfile(c);
  if (method === "DELETE" && path === "/v1/me") return deleteAccount(c);
  if (method === "POST" && path === "/v1/web/link-codes") return linkCode(c);
  if (method === "GET" && path === "/v1/web/session")
    return json({
      account: await profile(c.env, c.account),
      csrfToken: c.session?.csrf ?? "",
      expiresAt: c.session
        ? new Date(c.session.expires * 1000).toISOString()
        : null,
    });
  if (method === "DELETE" && path === "/v1/web/session") return logout(c);
  if (method === "POST" && path === "/v1/blocks") return blockAccount(c);
  if (method === "DELETE" && (m = /^\/v1\/blocks\/([^/]+)$/.exec(path)))
    return blockAccount(c, m[1]);
  if (method === "GET" && path === "/v1/blocks")
    return page(
      c,
      "SELECT blocked_id FROM blocks WHERE account_id=? ORDER BY blocked_id",
      [c.account.id],
      (r) => ({ accountID: r.blocked_id }),
    );
  if (method === "GET" && path === "/v1/library")
    return page(
      c,
      "SELECT * FROM history WHERE account_id=? ORDER BY first_encountered_at DESC,sermon_id",
      [c.account.id],
      (r) => ({
        sermonID: r.sermon_id,
        source: r.source,
        firstEncounteredAt: r.first_encountered_at,
      }),
    );
  if (method === "GET" && path === "/v1/cards")
    return page(
      c,
      `${cardSelect} WHERE c.owner_id=? ORDER BY c.created_at DESC,c.id`,
      [c.account.id],
      card,
    );
  if (method === "GET" && path === "/v1/offers")
    return page(
      c,
      "SELECT * FROM offers WHERE sender_id=? OR recipient_id=? ORDER BY created_at DESC,id",
      [c.account.id, c.account.id],
      offer,
    );
  if (method === "GET" && path === "/v1/inbox")
    return page(
      c,
      "SELECT * FROM inbox WHERE account_id=? ORDER BY created_at DESC,id",
      [c.account.id],
      (r) => ({
        id: r.id,
        type: r.type,
        resourceID: r.resource_id,
        createdAt: r.created_at,
        read: !!r.read,
      }),
    );
  if (method === "POST" && (m = /^\/v1\/inbox\/([^/]+)\/read$/.exec(path))) {
    noBody(c);
    await one(
      c.env,
      "SELECT id FROM inbox WHERE id=? AND account_id=?",
      m[1],
      c.account.id,
    );
    return command(c, { ok: true }, [
      sql(
        c.env,
        "UPDATE inbox SET read=1 WHERE id=? AND account_id=?",
        m[1],
        c.account.id,
      ),
    ]);
  }
  if (method === "POST" && path === "/v1/publications") return publish(c);
  if (method === "GET" && path === "/v1/publications")
    return page(
      c,
      "SELECT * FROM publications WHERE account_id=? ORDER BY created_at DESC,id",
      [c.account.id],
      publication,
    );
  if (method === "GET" && (m = /^\/v1\/publications\/([^/]+)$/.exec(path))) {
    const p = await publicationRow(c.env, m[1]);
    if (p.account_id !== c.account.id) {
      try {
        await requireRole(c, "moderator");
      } catch {
        await requireRole(c, "staff", p.church_id);
      }
    }
    return json({ publication: publication(p) });
  }
  if (
    method === "POST" &&
    (m = /^\/v1\/publications\/([^/]+)\/complete$/.exec(path))
  )
    return complete(c, m[1]);
  if (
    method === "POST" &&
    (m = /^\/v1\/sermons\/([^/]+)\/audio-url$/.exec(path))
  )
    return audioURL(c, m[1]);
  if (method === "POST" && (m = /^\/v1\/sermons\/([^/]+)\/keep$/.exec(path)))
    return keep(c, m[1]);
  if (method === "GET" && path === "/v1/packs/current")
    return json(packView(await getPack(c)));
  if (method === "POST" && (m = /^\/v1\/packs\/([^/]+)\/open$/.exec(path)))
    return openPack(c, m[1]);
  if (method === "POST" && path === "/v1/offers") return createOffer(c);
  if (method === "GET" && (m = /^\/v1\/offers\/([^/]+)$/.exec(path)))
    return preview(c, m[1]);
  if (
    method === "POST" &&
    (m =
      /^\/v1\/offers\/([^/]+)\/(accept|propose|confirm|decline|cancel)$/.exec(
        path,
      ))
  )
    return transition(c, m[1], m[2]);
  if (method === "POST" && path === "/v1/reports") return createReport(c);
  if (method === "POST" && path === "/v1/church-claims") return createClaim(c);
  if (method === "POST" && path === "/v1/appeals") return createAppeal(c);
  if (method === "GET" && path === "/v1/appeals")
    return page(
      c,
      "SELECT * FROM appeals WHERE account_id=? ORDER BY created_at DESC,id",
      [c.account.id],
      appeal,
    );
  if (method === "GET" && path === "/v1/moderation/queue") return queue(c);
  if (method === "POST" && path === "/v1/moderation/actions")
    return moderationAction(c);
  if (method === "GET" && path === "/v1/moderation/audit") {
    await requireRole(c, "moderator");
    return page(
      c,
      "SELECT * FROM audit ORDER BY created_at DESC,id",
      [],
      audit,
    );
  }
  if (method === "GET" && path === "/v1/portal/churches")
    return page(
      c,
      "SELECT DISTINCT ch.* FROM churches ch JOIN roles r ON r.church_id=ch.id OR r.role='admin' WHERE r.account_id=? AND r.role IN ('churchStaff','admin') ORDER BY ch.name,ch.id",
      [c.account.id],
      church,
    );
  if (
    method === "PATCH" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)$/.exec(path))
  )
    return churchProfile(c, m[1]);
  if (
    method === "GET" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/publications$/.exec(path))
  ) {
    await requireRole(c, "staff", m[1]);
    return page(
      c,
      `${reviewSelect} JOIN sermons s ON s.id=p.sermon_id WHERE s.church_id=? ORDER BY p.created_at DESC,p.id`,
      [c.account.id, c.account.id, m[1]],
      reviewedPublication,
    );
  }
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/sermons\/([^/]+)\/correct$/.exec(
      path,
    ))
  )
    return correction(c, m[1], m[2]);
  if (
    method === "POST" &&
    (m =
      /^\/v1\/portal\/churches\/([^/]+)\/publications\/([^/]+)\/decision$/.exec(
        path,
      ))
  )
    return churchDecision(c, m[1], m[2]);
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/official-audio$/.exec(path))
  ) {
    await requireRole(c, "staff", m[1]);
    return publish(c, m[1]);
  }
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/removals$/.exec(path))
  )
    return churchRemoval(c, m[1]);
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/services$/.exec(path))
  )
    return issueService(c, m[1]);
  if (
    method === "GET" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/services$/.exec(path))
  ) {
    await requireRole(c, "staff", m[1]);
    return page(
      c,
      "SELECT * FROM services WHERE church_id=? ORDER BY starts_at DESC,id",
      [m[1]],
      serviceView,
    );
  }
  if (
    method === "POST" &&
    (m = /^\/v1\/portal\/churches\/([^/]+)\/services\/([^/]+)\/revoke$/.exec(
      path,
    ))
  )
    return revokeService(c, m[1], m[2]);
  if (
    method === "GET" &&
    (m = /^\/portal\/services\/([^/]+)\/print$/.exec(path))
  )
    return printService(c, m[1]);
  if (method === "POST" && path === "/v1/shares") return createShare(c);
  fail(404, "not_found", "This endpoint could not be found.");
}
export async function scheduled(env: Env, cron: string): Promise<void> {
  await expireOffers(env);
  await recomputeCohorts(env);
  await cleanupDeletedObjects(env);
  const t = Math.floor(Date.now() / 1000);
  await env.DB.batch([
    sql(env, "DELETE FROM nonces WHERE expires<?", t),
    sql(env, "DELETE FROM sessions WHERE expires<?", t),
    sql(env, "DELETE FROM link_codes WHERE expires<?", t),
  ]);
  if (cron === "0 0 * * SUN") await buildPool(env);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      const publicResponse = await publicRoute(request, env, url);
      if (publicResponse) return publicResponse;
      if (
        !url.pathname.startsWith("/v1/") &&
        !/^\/portal\/services\/[^/]+\/print$/.test(url.pathname)
      ) {
        if (env.ASSETS) return env.ASSETS.fetch(request);
        fail(404, "not_found", "Static web files are not available yet.");
      }
      const { bytes, body } = await jsonBody(request);
      if (request.method === "POST" && url.pathname === "/v1/accounts") {
        const key = request.headers.get("Idempotency-Key");
        if (!key || !/^[A-Za-z0-9_-]{16,128}$/.test(key))
          fail(400, "invalid_request", "Provide an Idempotency-Key.");
        return await register(request, env, body, bytes);
      }
      if (request.method === "POST" && url.pathname === "/v1/web/session")
        return await webSession(request, env, body);
      const auth = await authenticate(request, env, bytes);
      const mutating = !["GET", "HEAD"].includes(request.method);
      const key =
        request.headers.get("Idempotency-Key") ??
        (request.method === "DELETE" && url.pathname === "/v1/web/session"
          ? uid()
          : "");
      if (mutating && !/^[A-Za-z0-9_-]{16,128}$/.test(key))
        fail(400, "invalid_request", "Provide an Idempotency-Key.");
      const c: Context = {
        request,
        url,
        env,
        bytes,
        body,
        ...auth,
        key,
        hash: await sha(
          request.method +
            "\n" +
            url.pathname +
            url.search +
            "\n" +
            (await sha(bytes)),
        ),
      };
      if (mutating) {
        const cached = await replay(c);
        if (cached) return json(cached);
      }
      return await accountRoute(c);
    } catch (error) {
      if (error instanceof APIError)
        return json(
          { error: { code: error.code, message: error.message } },
          error.status,
        );
      return json(
        {
          error: {
            code: "internal_error",
            message: "The service could not complete this request. Try again.",
          },
        },
        500,
      );
    }
  },
  async scheduled(controller: { cron: string }, env: Env): Promise<void> {
    await scheduled(env, controller.cron);
  },
};
