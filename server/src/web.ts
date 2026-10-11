import type { Context, Env, Row } from "./types";
import {
  checksum,
  command,
  fail,
  fields,
  json,
  now,
  num,
  one,
  sql,
  str,
  uid,
} from "./common";
import { capability, requireRole } from "./security";
import { getSermon } from "./projections";
export async function createShare(c: Context): Promise<Response> {
  const b = c.body;
  fields(
    b,
    ["sermonID", "byteCount", "checksumSHA256"],
    ["sermonID", "byteCount", "checksumSHA256"],
  );
  const sermonID = str(b.sermonID, 100)!;
  await getSermon(c.env, sermonID);
  const byteCount = num(b.byteCount, 8, 10000000, true),
    hash = checksum(b.checksumSHA256),
    id = uid(),
    expires = Math.floor(Date.now() / 1000) + 86400;
  return command(
    c,
    {
      shareID: id,
      uploadURL: `${c.env.PUBLIC_BASE_URL}/v1/share-images/${id}?token=${await capability(c.env, "image", id, expires)}`,
      url: `${c.env.PUBLIC_BASE_URL}/s/${id}`,
    },
    [
      sql(
        c.env,
        "INSERT INTO shares(id,account_id,sermon_id,storage_key,byte_count,checksum,upload_expires) VALUES(?,?,?,?,?,?,?)",
        id,
        c.account.id,
        sermonID,
        `public/cards/${id}.png`,
        byteCount,
        hash,
        expires,
      ),
    ],
  );
}
export async function shareData(env: Env, id: string): Promise<Row> {
  const share = await one(
    env,
    "SELECT * FROM shares WHERE id=? AND uploaded=1",
    id,
  );
  return {
    id,
    sermon: await getSermon(env, share.sermon_id),
    imageURL: `${env.PUBLIC_BASE_URL}/v1/share-images/${id}`,
    url: `${env.PUBLIC_BASE_URL}/s/${id}`,
    appURL: `${env.BRAND_SCHEME}://sermon/${share.sermon_id}`,
  };
}
export async function shareImage(
  request: Request,
  env: Env,
  id: string,
): Promise<Response> {
  const share = await one(
    env,
    "SELECT storage_key FROM shares WHERE id=? AND uploaded=1",
    id,
  );
  const object = await env.IMAGES.get(share.storage_key);
  if (!object) fail(404, "not_found", "This card image is unavailable.");
  return new Response(request.method === "HEAD" ? null : object.body, {
    headers: {
      "content-type": "image/png",
      "content-length": String(object.size),
      "x-content-type-options": "nosniff",
      "cache-control": "no-store",
      "API-Version": "1",
    },
  });
}
const escape = (value: unknown) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
async function render(
  env: Env,
  name: string,
  variables: Row,
  fallback: string,
): Promise<Response> {
  let template = fallback;
  if (env.ASSETS) {
    const response = await env.ASSETS.fetch(
      new Request(`${env.PUBLIC_BASE_URL}/templates/${name}.html`),
    );
    if (
      response.ok &&
      response.headers.get("content-type")?.includes("text/html")
    )
      template = await response.text();
  }
  const html = template.replace(/\{\{([A-Za-z][A-Za-z0-9]*)\}\}/g, (_, key) =>
    escape(variables[key]),
  );
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      "content-security-policy":
        "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
      "API-Version": "1",
    },
  });
}
export async function sharePage(env: Env, id: string): Promise<Response> {
  const data = await shareData(env, id);
  const s = data.sermon;
  const church = s.churchID
    ? await one(env, "SELECT name FROM churches WHERE id=?", s.churchID)
    : null;
  return render(
    env,
    "share",
    {
      brandName: env.BRAND_NAME,
      title: s.title,
      preacher: s.preacher,
      passage: s.primaryPassage,
      churchName: church?.name ?? "",
      city: s.city ?? "",
      summary: s.summary ?? "",
      reflectionPrompt: s.reflectionPrompt ?? "",
      imageURL: data.imageURL,
      shareURL: data.url,
      appURL: data.appURL,
      sermonID: s.id,
      audioStatus: s.audioAvailable ? "Audio available" : "Audio unavailable",
      fictionalLabel: s.fictional ? "Fictional sample" : "",
    },
    '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{title}} · {{brandName}}</title><main><h1>{{title}}</h1><p>{{fictionalLabel}}</p><img src="{{imageURL}}" alt="Card for {{title}}"><p>{{preacher}} · {{passage}} · {{churchName}} · {{city}}</p><p>{{summary}}</p><p>{{reflectionPrompt}}</p><p>{{audioStatus}}</p><a href="{{appURL}}">Open in app to listen</a></main></html>',
  );
}
export async function printService(c: Context, id: string): Promise<Response> {
  const svc = await one(c.env, "SELECT * FROM services WHERE id=?", id);
  await requireRole(c, "staff", svc.church_id);
  if (svc.revoked || Date.parse(svc.expires_at) <= Date.now())
    fail(410, "expired", "This permission is revoked or expired.");
  const church = await one(
    c.env,
    "SELECT name FROM churches WHERE id=?",
    svc.church_id,
  );
  return render(
    c.env,
    "service-print",
    {
      brandName: c.env.BRAND_NAME,
      churchName: church.name,
      service: svc.service,
      startsAt: svc.starts_at,
      expiresAt: svc.expires_at,
      recordingAllowed: svc.recording_allowed ? "Yes" : "No",
      publicSharingAllowed: svc.public_sharing_allowed ? "Yes" : "No",
      reviewRequired: svc.review_required ? "Yes" : "No",
      token: svc.token,
      qrValue: svc.token,
      serviceID: id,
    },
    '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{churchName}} service permission · {{brandName}}</title><main><h1>{{churchName}} · {{service}}</h1><p>{{startsAt}} · Expires {{expiresAt}}</p><dl><dt>Recording allowed</dt><dd>{{recordingAllowed}}</dd><dt>Public sharing allowed</dt><dd>{{publicSharingAllowed}}</dd><dt>Church review required</dt><dd>{{reviewRequired}}</dd></dl><p>QR layout is unavailable. This is the signed service token:</p><code>{{token}}</code></main></html>',
  );
}
