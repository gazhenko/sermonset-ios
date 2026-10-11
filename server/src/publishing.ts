import type { Context, Env, Row, Statement } from "./types";
import {
  choice,
  checksum,
  command,
  date,
  event,
  fail,
  fields,
  guard,
  json,
  noBody,
  normalized,
  now,
  num,
  one,
  page,
  sql,
  str,
  uid,
  bool,
} from "./common";
import {
  capability,
  checkCapability,
  hmac,
  requireRole,
  verifyToken,
} from "./security";
import { authorizedSQL, publication } from "./projections";

export function approvalStatements(
  c: Context,
  p: Row,
  basis = "churchReview",
): Statement[] {
  const env = c.env,
    grantorID = c.account.id;
  const stmts = [
    guard(
      env,
      "EXISTS(SELECT 1 FROM publications WHERE id=? AND state='pendingRights')",
      p.id,
    ),
    guard(
      env,
      "EXISTS(SELECT 1 FROM sermons WHERE id=? AND (state NOT IN ('removed','disputed') OR ?='official'))",
      p.sermon_id,
      p.kind ?? null,
    ),
  ];
  if (p.audio_asset_id) {
    stmts.push(
      guard(
        env,
        "EXISTS(SELECT 1 FROM audio_assets WHERE id=? AND validated=1 AND uploaded=1)",
        p.audio_asset_id,
      ),
    );
    if (!p.church_id)
      fail(
        403,
        "forbidden",
        "Audio approval requires a verified church or scoped service grant.",
      );
    stmts.push(
      guard(
        env,
        "EXISTS(SELECT 1 FROM churches WHERE id=? AND verified=1)",
        p.church_id,
      ),
    );
    if (p.service_id)
      stmts.push(
        guard(
          env,
          "EXISTS(SELECT 1 FROM services WHERE id=? AND revoked=0 AND public_sharing_allowed=1 AND julianday(expires_at)>julianday('now'))",
          p.service_id,
        ),
      );
    stmts.push(
      sql(
        env,
        "INSERT INTO grants(asset_id,church_id,service_id,grantor_id,active,expires_at,basis) VALUES(?,?,?,?,1,(SELECT expires_at FROM services WHERE id=?),?) ON CONFLICT(asset_id) DO UPDATE SET active=1,grantor_id=excluded.grantor_id,basis=excluded.basis",
        p.audio_asset_id,
        p.church_id,
        p.service_id,
        grantorID,
        p.service_id,
        basis,
      ),
      sql(
        env,
        "UPDATE audio_assets SET state='approved' WHERE id=?",
        p.audio_asset_id,
      ),
    );
    if (p.kind === "official") {
      stmts.push(
        sql(
          env,
          "UPDATE audio_assets SET state='superseded' WHERE id=(SELECT canonical_audio_id FROM sermons WHERE id=?) AND id<>?",
          p.sermon_id,
          p.audio_asset_id,
        ),
        sql(
          env,
          "UPDATE publications SET state='superseded' WHERE audio_asset_id=(SELECT canonical_audio_id FROM sermons WHERE id=?) AND id<>?",
          p.sermon_id,
          p.id,
        ),
        sql(
          env,
          "UPDATE sermons SET canonical_audio_id=? WHERE id=?",
          p.audio_asset_id,
          p.sermon_id,
        ),
      );
    } else
      stmts.push(
        sql(
          env,
          "UPDATE sermons SET canonical_audio_id=? WHERE id=? AND canonical_audio_id IS NULL",
          p.audio_asset_id,
          p.sermon_id,
        ),
      );
    stmts.push(
      sql(
        env,
        "UPDATE audio_assets SET state='published' WHERE id=?",
        p.audio_asset_id,
      ),
    );
  }
  stmts.push(
    sql(env, "UPDATE publications SET state='approved' WHERE id=?", p.id),
    sql(env, "UPDATE publications SET state='published' WHERE id=?", p.id),
    sql(
      env,
      "UPDATE sermons SET state='published',church_verified=CASE WHEN EXISTS(SELECT 1 FROM churches WHERE id=? AND verified=1) THEN 1 ELSE church_verified END WHERE id=?",
      p.church_id,
      p.sermon_id,
    ),
  );
  if (p.account_id)
    stmts.push(event(c, p.account_id, "publicationPublished", p.id));
  return stmts;
}
export async function publish(
  c: Context,
  churchRouteID?: string,
): Promise<Response> {
  const b = c.body;
  fields(
    b,
    [
      "title",
      "preacher",
      "churchID",
      "service",
      "serviceDate",
      "primaryPassage",
      "themes",
      "sermonType",
      "city",
      "region",
      "country",
      "summary",
      "reflectionPrompt",
      "reviewed",
      "checklist",
      "rightsBasis",
      "serviceToken",
      "audio",
    ],
    [
      "title",
      "preacher",
      "serviceDate",
      "primaryPassage",
      "themes",
      "sermonType",
      "reviewed",
      "checklist",
      "rightsBasis",
    ],
  );
  const title = str(b.title, 200)!,
    preacher = str(b.preacher, 120)!,
    passage = str(b.primaryPassage, 150)!,
    type = str(b.sermonType, 60)!,
    serviceDate = date(b.serviceDate);
  if (b.reviewed !== true)
    fail(
      400,
      "invalid_request",
      "Review the public metadata before publishing.",
    );
  fields(
    b.checklist,
    [
      "musicReviewed",
      "prayerRequestsReviewed",
      "childrenReviewed",
      "privateTalkReviewed",
    ],
    [
      "musicReviewed",
      "prayerRequestsReviewed",
      "childrenReviewed",
      "privateTalkReviewed",
    ],
  );
  if (Object.values(b.checklist).some((v) => v !== true))
    fail(400, "invalid_request", "Complete the sensitive-content checklist.");
  if (!Array.isArray(b.themes) || b.themes.length > 12)
    fail(400, "invalid_request", "Supply up to twelve themes.");
  b.themes.forEach((v: unknown) => str(v, 60));
  const basis = choice(b.rightsBasis, [
    "none",
    "churchReview",
    "serviceQR",
    "official",
  ]);
  let churchID = b.churchID === undefined ? null : str(b.churchID, 100, true);
  let serviceID: string | null = null;
  for (const k of [
    "service",
    "city",
    "region",
    "country",
    "summary",
    "reflectionPrompt",
  ])
    if (b[k] !== undefined)
      str(b[k], ["summary", "reflectionPrompt"].includes(k) ? 1200 : 120, true);
  if (churchID)
    await one(c.env, "SELECT id FROM churches WHERE id=?", churchID);
  if (churchRouteID && (churchRouteID !== churchID || basis !== "official"))
    fail(400, "invalid_request", "Official publication must match the church.");
  if (basis === "official") {
    if (!churchID)
      fail(400, "invalid_request", "Choose the church for official audio.");
    await requireRole(c, "staff", churchID);
    if (!b.audio)
      fail(400, "invalid_request", "Official audio requires an audio upload.");
  }
  if (b.audio && (!churchID || basis === "none"))
    fail(
      403,
      "forbidden",
      "A verified rights basis is required for public audio.",
    );
  if (basis === "serviceQR") {
    const token = await verifyToken(c.env, b.serviceToken, "service+jwt");
    const svc = await one(c.env, "SELECT * FROM services WHERE id=?", token.id);
    if (
      svc.revoked ||
      !svc.public_sharing_allowed ||
      Date.parse(svc.expires_at) <= Date.now() ||
      svc.church_id !== churchID ||
      svc.service !== b.service ||
      Math.abs(Date.parse(svc.starts_at) - Date.parse(serviceDate)) > 86400000
    )
      fail(
        403,
        "forbidden",
        "This service permission does not cover this publication.",
      );
    serviceID = svc.id;
  } else if (b.serviceToken !== undefined)
    fail(
      400,
      "invalid_request",
      "Service token requires the serviceQR rights basis.",
    );
  let assetID: string | null = null,
    expires: number | null = null,
    uploadURL: string | null = null;
  if (b.audio) {
    fields(
      b.audio,
      [
        "byteCount",
        "duration",
        "checksumSHA256",
        "contentType",
        "trimStart",
        "trimEnd",
        "sourceChecksumSHA256",
      ],
      [
        "byteCount",
        "duration",
        "checksumSHA256",
        "contentType",
        "trimStart",
        "trimEnd",
        "sourceChecksumSHA256",
      ],
    );
    num(b.audio.byteCount, 32, 200000000, true);
    num(b.audio.duration, 0.1, 10800);
    checksum(b.audio.checksumSHA256);
    checksum(b.audio.sourceChecksumSHA256);
    choice(b.audio.contentType, ["audio/mp4"]);
    num(b.audio.trimStart, 0, 86400);
    num(b.audio.trimEnd, 0.1, 97200);
    if (
      b.audio.trimEnd <= b.audio.trimStart ||
      Math.abs(b.audio.trimEnd - b.audio.trimStart - b.audio.duration) > 0.1 ||
      b.audio.sourceChecksumSHA256 === b.audio.checksumSHA256
    )
      fail(
        400,
        "invalid_request",
        "Upload a reviewed trim derivative with original provenance.",
      );
    assetID = uid();
    expires = Math.floor(Date.now() / 1000) + 86400;
    uploadURL = `${c.env.PUBLIC_BASE_URL}/v1/uploads/${assetID}?token=${await capability(c.env, "upload", assetID, expires)}`;
  }
  const pubID = uid(),
    candidateID = uid(),
    time = now();
  const titleNorm = normalized(title),
    passageNorm = normalized(passage);
  // Matching is repeated inside the transaction; simultaneous contributors cannot create duplicates.
  const match = `SELECT id FROM sermons WHERE church_id=? AND abs(julianday(service_date)-julianday(?))<=1 AND (title_normalized=? OR (passage_normalized<>'' AND passage_normalized=?)) ORDER BY created_at,id LIMIT 1`;
  const args = [churchID, serviceDate, titleNorm, passageNorm];
  const selected = churchID ? `COALESCE((${match}),?)` : "?";
  const selectedArgs = churchID ? [...args, candidateID] : [candidateID];
  const stmts: Statement[] = [
    sql(
      c.env,
      `INSERT INTO sermons(id,church_id,title,title_normalized,preacher,service,service_date,primary_passage,passage_normalized,themes,sermon_type,city,region,country,summary,reflection_prompt,state,created_at)
 SELECT ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'pendingRights',? WHERE ${churchID ? `NOT EXISTS(${match})` : "1=1"}`,
      candidateID,
      churchID,
      title,
      titleNorm,
      preacher,
      b.service ?? null,
      serviceDate,
      passage,
      passageNorm,
      JSON.stringify(b.themes),
      type,
      b.city ?? null,
      b.region ?? null,
      b.country ?? null,
      b.summary ?? null,
      b.reflectionPrompt ?? null,
      time,
      ...(churchID ? args : []),
    ),
    sql(
      c.env,
      `INSERT INTO publications(id,account_id,sermon_id,state,rights_basis,service_id,audio_asset_id,created_at) VALUES(?,?,${selected},?,?,?,?,?)`,
      pubID,
      c.account.id,
      ...selectedArgs,
      assetID ? "pendingUpload" : "pendingRights",
      basis,
      serviceID,
      assetID,
      time,
    ),
    sql(
      c.env,
      "INSERT OR IGNORE INTO contributors(sermon_id,account_id) SELECT sermon_id,? FROM publications WHERE id=?",
      c.account.id,
      pubID,
    ),
  ];
  const review = {
    title,
    preacher,
    serviceDate,
    primaryPassage: passage,
    sermonType: type,
    themes: b.themes,
    summary: b.summary ?? null,
    reflectionPrompt: b.reflectionPrompt ?? null,
    checklist: b.checklist,
  };
  stmts.push(
    sql(
      c.env,
      "UPDATE publications SET review_metadata=? WHERE id=?",
      JSON.stringify(review),
      pubID,
    ),
  );
  if (assetID)
    stmts.push(
      sql(
        c.env,
        `INSERT INTO audio_assets(id,publication_id,owner_id,sermon_id,storage_key,checksum,source_checksum,byte_count,duration,trim_start,trim_end,kind,state,upload_expires)
 SELECT ?,?,?,sermon_id,?,?,?,?,?,?,?,?,'pendingUpload',? FROM publications WHERE id=?`,
        assetID,
        pubID,
        c.account.id,
        `private/audio/${assetID}`,
        b.audio.checksumSHA256,
        b.audio.sourceChecksumSHA256,
        b.audio.byteCount,
        b.audio.duration,
        b.audio.trimStart,
        b.audio.trimEnd,
        basis === "official" ? "official" : "enhancedCommunity",
        expires,
        pubID,
      ),
    );
  return command(c, {}, stmts, {
    query:
      "SELECT json_object('publicationID',id,'sermonID',sermon_id,'audioAssetID',audio_asset_id,'uploadURL',?) FROM publications WHERE id=?",
    args: [uploadURL, pubID],
  });
}
export const publicationRow = (env: Env, id: string) =>
  one(
    env,
    "SELECT p.*,s.church_id,a.kind,a.validated,a.uploaded FROM publications p JOIN sermons s ON s.id=p.sermon_id LEFT JOIN audio_assets a ON a.id=p.audio_asset_id WHERE p.id=?",
    id,
  );
export async function complete(c: Context, id: string): Promise<Response> {
  noBody(c);
  const p = await publicationRow(c.env, id);
  if (p.account_id !== c.account.id)
    fail(403, "forbidden", "Only the contributor can complete this upload.");
  if (
    !p.audio_asset_id ||
    !p.uploaded ||
    !p.validated ||
    p.state !== "quarantine"
  )
    fail(
      409,
      "conflict",
      "Upload valid audio before completing this publication.",
    );
  const stmts = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM publications WHERE id=? AND state='quarantine')",
      id,
    ),
    sql(c.env, "UPDATE publications SET state='validating' WHERE id=?", id),
    sql(
      c.env,
      "UPDATE audio_assets SET state='validating' WHERE id=?",
      p.audio_asset_id,
    ),
    sql(c.env, "UPDATE publications SET state='pendingRights' WHERE id=?", id),
    sql(
      c.env,
      "UPDATE audio_assets SET state='pendingRights' WHERE id=?",
      p.audio_asset_id,
    ),
  ];
  let automatic = p.rights_basis === "official";
  if (p.service_id) {
    const svc = await one(
      c.env,
      "SELECT * FROM services WHERE id=?",
      p.service_id,
    );
    automatic =
      !svc.review_required &&
      !svc.revoked &&
      svc.public_sharing_allowed &&
      Date.parse(svc.expires_at) > Date.now();
  }
  if (automatic) {
    if (p.rights_basis === "official")
      await requireRole(c, "staff", p.church_id);
    stmts.push(
      ...approvalStatements(
        c,
        { ...p, state: "pendingRights" },
        p.rights_basis,
      ),
    );
  }
  return command(c, { ok: true, publicationID: id }, stmts);
}
export async function audioURL(
  c: Context,
  sermonID: string,
): Promise<Response> {
  noBody(c);
  const a = await sql(
    c.env,
    `SELECT a.* FROM audio_assets a JOIN grants g ON g.asset_id=a.id JOIN sermons s ON s.id=a.sermon_id WHERE s.id=? AND s.canonical_audio_id=a.id AND s.state='published' AND ${authorizedSQL}`,
    sermonID,
  ).first();
  if (!a)
    fail(
      410,
      "audio_unavailable",
      "Audio is unavailable. The card and library history remain.",
    );
  const expires = Math.floor(Date.now() / 1000) + 300;
  return command(
    c,
    {
      url: `${c.env.PUBLIC_BASE_URL}/v1/audio/${a.id}?expires=${expires}&signature=${await hmac(c.env, `audio\n${a.id}\n${expires}`)}`,
      expiresAt: new Date(expires * 1000).toISOString(),
      audioAssetID: a.id,
      alignmentWarning:
        a.kind === "official" ? "Your moments may shift." : null,
    },
    [],
  );
}
export async function listen(
  request: Request,
  env: Env,
  id: string,
  url: URL,
): Promise<Response> {
  const expires = url.searchParams.get("expires");
  const signature = url.searchParams.get("signature");
  await checkCapability(env, "audio", id, `${expires}.${signature}`);
  const a = await sql(
    env,
    `SELECT a.* FROM audio_assets a JOIN grants g ON g.asset_id=a.id JOIN sermons s ON s.id=a.sermon_id WHERE a.id=? AND s.state='published' AND ${authorizedSQL}`,
    id,
  ).first();
  if (!a)
    fail(
      410,
      "audio_unavailable",
      "Audio is unavailable. The card and history remain.",
    );
  return serveAsset(request, env, a);
}
export async function previewURL(
  c: Context,
  id: string,
  churchID?: string,
): Promise<Response> {
  noBody(c);
  const p = await publicationRow(c.env, id);
  if (churchID) {
    await requireRole(c, "staff", churchID);
    if (p.church_id !== churchID)
      fail(403, "forbidden", "This publication belongs to another church.");
  } else await requireRole(c, "moderator");
  if (
    !p.audio_asset_id ||
    !p.uploaded ||
    !p.validated ||
    !["quarantine", "pendingRights", "published"].includes(p.state)
  )
    fail(409, "conflict", "Validated reviewer audio is not available.");
  const expires = Math.floor(Date.now() / 1000) + 300;
  const token = await capability(
    c.env,
    "review",
    p.audio_asset_id + "\n" + c.account.id,
    expires,
  );
  return command(
    c,
    {
      url: `${c.env.PUBLIC_BASE_URL}/v1/review-audio/${p.audio_asset_id}?token=${token}`,
      expiresAt: new Date(expires * 1000).toISOString(),
    },
    [],
  );
}
export async function reviewListen(c: Context, id: string): Promise<Response> {
  await checkCapability(
    c.env,
    "review",
    id + "\n" + c.account.id,
    c.url.searchParams.get("token"),
  );
  const a = await one(
    c.env,
    "SELECT a.*,s.church_id FROM audio_assets a JOIN sermons s ON s.id=a.sermon_id WHERE a.id=? AND a.validated=1 AND a.uploaded=1 AND a.state IN ('quarantine','pendingRights','published')",
    id,
  );
  try {
    await requireRole(c, "moderator");
  } catch {
    await requireRole(c, "staff", a.church_id);
  }
  return serveAsset(c.request, c.env, a);
}
async function serveAsset(
  request: Request,
  env: Env,
  a: Row,
): Promise<Response> {
  const object = await env.AUDIO.head(a.storage_key);
  if (!object) fail(410, "audio_unavailable", "Audio is unavailable.");
  const headers: Record<string, string> = {
    "content-type": "audio/mp4",
    "accept-ranges": "bytes",
    "cache-control": "private, no-store",
    "x-content-type-options": "nosniff",
    "API-Version": "1",
  };
  let start = 0,
    end = object.size - 1,
    status = 200;
  const range = request.headers.get("range");
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (!m || (!m[1] && !m[2]))
      return new Response(null, {
        status: 416,
        headers: { ...headers, "content-range": `bytes */${object.size}` },
      });
    if (!m[1]) start = Math.max(0, object.size - Number(m[2]));
    else {
      start = Number(m[1]);
      if (m[2]) end = Math.min(end, Number(m[2]));
    }
    if (start > end || start >= object.size)
      return new Response(null, {
        status: 416,
        headers: { ...headers, "content-range": `bytes */${object.size}` },
      });
    status = 206;
    headers["content-range"] = `bytes ${start}-${end}/${object.size}`;
  }
  headers["content-length"] = String(end - start + 1);
  if (request.method === "HEAD") return new Response(null, { status, headers });
  const data = await env.AUDIO.get(a.storage_key, {
    range: { offset: start, length: end - start + 1 },
  });
  if (!data) fail(410, "audio_unavailable", "Audio is unavailable.");
  return new Response(data.body, { status, headers });
}
