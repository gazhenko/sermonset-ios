import type { Context, Env, Row, Statement } from "./types";
import {
  bool,
  choice,
  command,
  date,
  event,
  fail,
  fields,
  guard,
  noBody,
  now,
  num,
  one,
  page,
  sql,
  str,
  uid,
  website,
  normalized,
} from "./common";
import { requireRole, signToken } from "./security";
import { approvalStatements, publicationRow } from "./publishing";
import {
  appeal,
  audit,
  claim,
  publication,
  report,
  reviewSelect,
  reviewedPublication,
} from "./projections";
export async function createReport(c: Context): Promise<Response> {
  const b = c.body;
  fields(
    b,
    ["targetType", "targetID", "reason", "timestamp", "details"],
    ["targetType", "targetID", "reason"],
  );
  const type = choice(b.targetType, ["sermon", "audio", "card", "account"]);
  const id = str(b.targetID, 100)!;
  const table = {
    sermon: "sermons",
    audio: "audio_assets",
    card: "cards",
    account: "accounts",
  }[type];
  await one(c.env, `SELECT id FROM ${table} WHERE id=?`, id);
  const reason = choice(b.reason, [
    "rights",
    "privacy",
    "wrongAttribution",
    "misleadingEdit",
    "sensitiveContent",
    "abuse",
  ]);
  const timestamp =
    b.timestamp === undefined ? null : num(b.timestamp, 0, 10800);
  if (timestamp !== null && !["sermon", "audio"].includes(type))
    fail(400, "invalid_request", "Timestamps apply to audio or sermons.");
  const details = b.details === undefined ? null : str(b.details, 2000, true),
    reportID = uid();
  return command(c, { ok: true, reportID }, [
    sql(
      c.env,
      "INSERT INTO reports(id,reporter_id,target_type,target_id,reason,timestamp,details,created_at) VALUES(?,?,?,?,?,?,?,?)",
      reportID,
      c.account.id,
      type,
      id,
      reason,
      timestamp,
      details,
      now(),
    ),
  ]);
}
export async function createClaim(c: Context): Promise<Response> {
  const b = c.body;
  fields(
    b,
    ["churchID", "name", "website", "role", "evidence"],
    ["name", "website", "role", "evidence"],
  );
  const churchID = b.churchID === undefined ? null : str(b.churchID, 100)!;
  if (churchID)
    await one(c.env, "SELECT id FROM churches WHERE id=?", churchID);
  const claimID = uid();
  return command(c, { ok: true, claimID }, [
    sql(
      c.env,
      "INSERT INTO claims(id,account_id,church_id,name,website,role,evidence,created_at) VALUES(?,?,?,?,?,?,?,?)",
      claimID,
      c.account.id,
      churchID,
      str(b.name, 150),
      website(b.website),
      str(b.role, 150),
      str(b.evidence, 3000),
      now(),
    ),
  ]);
}
export async function createAppeal(c: Context): Promise<Response> {
  fields(c.body, ["actionID", "reason"], ["actionID", "reason"]);
  const action = await one(
    c.env,
    "SELECT * FROM audit WHERE id=?",
    str(c.body.actionID, 100),
  );
  if (action.affected_account_id !== c.account.id)
    fail(403, "forbidden", "Only the affected account may appeal.");
  const appealID = uid();
  return command(c, { ok: true, appealID }, [
    sql(
      c.env,
      "INSERT INTO appeals(id,account_id,action_id,reason,created_at) VALUES(?,?,?,?,?)",
      appealID,
      c.account.id,
      action.id,
      str(c.body.reason, 3000),
      now(),
    ),
  ]);
}
export async function queue(c: Context): Promise<Response> {
  await requireRole(c, "moderator");
  const kind = choice(c.url.searchParams.get("kind") ?? "reports", [
    "reports",
    "publications",
    "claims",
    "appeals",
    "removals",
  ]);
  const config = {
    reports: {
      q: `SELECT r.*,CASE r.target_type WHEN 'sermon' THEN (SELECT title FROM sermons WHERE id=r.target_id) WHEN 'audio' THEN (SELECT s.title FROM audio_assets a JOIN sermons s ON s.id=a.sermon_id WHERE a.id=r.target_id) WHEN 'card' THEN (SELECT 'Card #' || serial_number FROM cards WHERE id=r.target_id) ELSE 'Account' END AS target_summary FROM reports r WHERE r.state='open' ORDER BY r.created_at,r.id`,
      p: report,
    },
    publications: {
      q: `${reviewSelect} WHERE p.state='pendingRights' ORDER BY p.created_at,p.id`,
      p: reviewedPublication,
    },
    claims: {
      q: "SELECT * FROM claims WHERE state='open' ORDER BY created_at,id",
      p: claim,
    },
    appeals: {
      q: "SELECT * FROM appeals WHERE state='open' ORDER BY created_at,id",
      p: appeal,
    },
    removals: {
      q: "SELECT * FROM removals ORDER BY created_at DESC,id",
      p: (r: Row) => ({
        id: r.id,
        churchID: r.church_id,
        sermonID: r.sermon_id,
        accountID: r.account_id,
        reason: r.reason,
        createdAt: r.created_at,
      }),
    },
  }[kind];
  return page(
    c,
    config.q,
    kind === "publications" ? [c.account.id, c.account.id] : [],
    config.p,
  );
}
function auditStatement(
  c: Context,
  id: string,
  type: string,
  targetID: string,
  action: string,
  reason: string,
  affected: string | null,
): Statement {
  return sql(
    c.env,
    "INSERT INTO audit(id,actor_id,affected_account_id,target_type,target_id,action,reason,created_at) VALUES(?,?,?,?,?,?,?,?)",
    id,
    c.account.id,
    affected,
    type,
    targetID,
    action,
    reason,
    now(),
  );
}
export function removalStatements(
  env: Env,
  sermonID: string,
  state: "removed" | "disputed",
): Statement[] {
  return [
    sql(env, "UPDATE sermons SET state=? WHERE id=?", state, sermonID),
    sql(
      env,
      "UPDATE publications SET state=? WHERE sermon_id=? AND state IN ('published','approved','disputed','removed')",
      state,
      sermonID,
    ),
    sql(
      env,
      "UPDATE audio_assets SET state=? WHERE sermon_id=? AND state IN ('published','approved','disputed','removed')",
      state,
      sermonID,
    ),
    sql(
      env,
      "UPDATE grants SET active=0 WHERE asset_id IN (SELECT id FROM audio_assets WHERE sermon_id=?)",
      sermonID,
    ),
  ];
}
export async function moderationAction(c: Context): Promise<Response> {
  await requireRole(c, "moderator");
  const b = c.body;
  fields(
    b,
    ["targetType", "targetID", "action", "reason"],
    ["targetType", "targetID", "action", "reason"],
  );
  const type = choice(b.targetType, [
      "publication",
      "sermon",
      "audio",
      "account",
      "claim",
      "report",
      "appeal",
    ]),
    action = choice(b.action, [
      "approve",
      "reject",
      "dispute",
      "remove",
      "restore",
      "ban",
      "unban",
      "resolve",
    ]);
  const targetID = str(b.targetID, 100)!,
    reason = str(b.reason, 3000)!,
    actionID = uid();
  let affected: string | null = null;
  const statements: Statement[] = [];
  if (type === "publication") {
    const p = await publicationRow(c.env, targetID);
    affected = p.account_id;
    if (action === "approve") {
      statements.push(...approvalStatements(c, p));
    } else if (action === "reject") {
      if (!["pendingRights", "quarantine", "pendingUpload"].includes(p.state))
        fail(
          409,
          "conflict",
          "This publication cannot be rejected in its current state.",
        );
      statements.push(
        guard(
          c.env,
          "EXISTS(SELECT 1 FROM publications WHERE id=? AND state=?)",
          p.id,
          p.state,
        ),
        sql(c.env, "UPDATE publications SET state='rejected' WHERE id=?", p.id),
        sql(
          c.env,
          "UPDATE audio_assets SET state='rejected' WHERE id=?",
          p.audio_asset_id,
        ),
      );
      if (p.account_id)
        statements.push(event(c, p.account_id, "publicationRejected", p.id));
    } else
      fail(400, "invalid_request", "Use approve or reject for a publication.");
  } else if (type === "claim") {
    const cl = await one(c.env, "SELECT * FROM claims WHERE id=?", targetID);
    affected = cl.account_id;
    if (!["approve", "reject"].includes(action) || cl.state !== "open")
      fail(409, "conflict", "This claim is not awaiting a decision.");
    statements.push(
      guard(
        c.env,
        "EXISTS(SELECT 1 FROM claims WHERE id=? AND state='open')",
        targetID,
      ),
    );
    if (action === "approve") {
      const churchID = cl.church_id ?? uid();
      if (!cl.church_id)
        statements.push(
          sql(
            c.env,
            "INSERT INTO churches(id,name,website,verified) VALUES(?,?,?,1)",
            churchID,
            cl.name,
            cl.website,
          ),
        );
      else
        statements.push(
          sql(c.env, "UPDATE churches SET verified=1 WHERE id=?", churchID),
        );
      statements.push(
        sql(
          c.env,
          "INSERT OR IGNORE INTO roles(account_id,role,church_id) VALUES(?,'churchStaff',?)",
          cl.account_id,
          churchID,
        ),
        sql(
          c.env,
          "UPDATE claims SET church_id=? WHERE id=?",
          churchID,
          targetID,
        ),
      );
    }
    statements.push(
      sql(
        c.env,
        "UPDATE claims SET state=? WHERE id=?",
        action === "approve" ? "approved" : "rejected",
        targetID,
      ),
      event(
        c,
        cl.account_id,
        "churchClaim" + (action === "approve" ? "Approved" : "Rejected"),
        targetID,
      ),
    );
  } else if (type === "account") {
    await requireRole(c, "admin");
    await one(c.env, "SELECT id FROM accounts WHERE id=?", targetID);
    affected = targetID;
    if (!["ban", "unban"].includes(action))
      fail(400, "invalid_request", "Choose ban or unban.");
    if (targetID === c.account.id)
      fail(
        400,
        "invalid_request",
        "An admin cannot ban their own active account.",
      );
    statements.push(
      sql(
        c.env,
        "UPDATE accounts SET banned=? WHERE id=?",
        action === "ban" ? 1 : 0,
        targetID,
      ),
    );
    if (action === "ban")
      statements.push(
        sql(
          c.env,
          "UPDATE offers SET state='cancelled' WHERE state IN ('open','proposed') AND (sender_id=? OR recipient_id=?)",
          targetID,
          targetID,
        ),
        sql(c.env, "DELETE FROM sessions WHERE account_id=?", targetID),
      );
    statements.push(
      event(
        c,
        targetID,
        "account" + (action === "ban" ? "Banned" : "Restored"),
        targetID,
      ),
    );
  } else if (type === "report" || type === "appeal") {
    const row = await one(
      c.env,
      `SELECT * FROM ${type === "report" ? "reports" : "appeals"} WHERE id=?`,
      targetID,
    );
    affected = type === "report" ? row.reporter_id : row.account_id;
    if (
      !["resolve", "approve", "reject"].includes(action) ||
      row.state !== "open"
    )
      fail(409, "conflict", "This item is not awaiting a decision.");
    statements.push(
      guard(
        c.env,
        `EXISTS(SELECT 1 FROM ${type === "report" ? "reports" : "appeals"} WHERE id=? AND state='open')`,
        targetID,
      ),
      sql(
        c.env,
        `UPDATE ${type === "report" ? "reports" : "appeals"} SET state=? WHERE id=?`,
        action === "reject" ? "rejected" : "resolved",
        targetID,
      ),
    );
    if (affected)
      statements.push(event(c, affected, type + "Resolved", targetID));
  } else if (type === "sermon" || type === "audio") {
    const s =
      type === "sermon"
        ? await one(c.env, "SELECT * FROM sermons WHERE id=?", targetID)
        : await one(
            c.env,
            "SELECT s.*,a.owner_id,a.state AS asset_state FROM audio_assets a JOIN sermons s ON s.id=a.sermon_id WHERE a.id=?",
            targetID,
          );
    affected =
      type === "audio"
        ? s.owner_id
        : ((
            await sql(
              c.env,
              "SELECT account_id FROM publications WHERE sermon_id=? ORDER BY created_at LIMIT 1",
              s.id,
            ).first()
          )?.account_id ?? null);
    const currentState = type === "sermon" ? s.state : s.asset_state;
    const validStates: Record<string, string[]> = {
      dispute: ["published"],
      remove: ["published", "disputed"],
      restore: ["disputed", "removed"],
    };
    if (validStates[action] && !validStates[action].includes(currentState))
      fail(
        409,
        "conflict",
        "This moderation transition is not valid in the current state.",
      );
    statements.push(
      guard(
        c.env,
        `EXISTS(SELECT 1 FROM ${type === "sermon" ? "sermons" : "audio_assets"} WHERE id=? AND state=?)`,
        targetID,
        currentState,
      ),
    );
    if (action === "remove" || action === "dispute") {
      if (type === "sermon" || s.canonical_audio_id === targetID)
        statements.push(
          ...removalStatements(
            c.env,
            s.id,
            action === "remove" ? "removed" : "disputed",
          ),
        );
      else
        statements.push(
          sql(
            c.env,
            "UPDATE audio_assets SET state=? WHERE id=?",
            action === "remove" ? "removed" : "disputed",
            targetID,
          ),
          sql(
            c.env,
            "UPDATE publications SET state=? WHERE audio_asset_id=?",
            action === "remove" ? "removed" : "disputed",
            targetID,
          ),
          sql(c.env, "UPDATE grants SET active=0 WHERE asset_id=?", targetID),
        );
    } else if (action === "restore") {
      const assetID = type === "audio" ? targetID : s.canonical_audio_id;
      if (assetID) {
        const grant = await one(
          c.env,
          "SELECT g.*,sv.revoked,sv.public_sharing_allowed,sv.expires_at AS service_expires,a.validated FROM grants g JOIN audio_assets a ON a.id=g.asset_id LEFT JOIN services sv ON sv.id=g.service_id WHERE g.asset_id=?",
          assetID,
        );
        if (
          !grant.validated ||
          grant.church_id !== s.church_id ||
          (grant.expires_at && Date.parse(grant.expires_at) <= Date.now()) ||
          (grant.service_id &&
            (grant.revoked ||
              !grant.public_sharing_allowed ||
              Date.parse(grant.service_expires) <= Date.now()))
        )
          fail(
            403,
            "forbidden",
            "Renew the rights grant before restoring audio.",
          );
        statements.push(
          guard(
            c.env,
            "EXISTS(SELECT 1 FROM grants g JOIN audio_assets a ON a.id=g.asset_id JOIN churches ch ON ch.id=g.church_id JOIN sermons s ON s.id=a.sermon_id WHERE g.asset_id=? AND g.church_id=s.church_id AND a.validated=1 AND ch.verified=1 AND (g.expires_at IS NULL OR julianday(g.expires_at)>julianday('now')) AND (g.service_id IS NULL OR EXISTS(SELECT 1 FROM services WHERE id=g.service_id AND revoked=0 AND public_sharing_allowed=1 AND julianday(expires_at)>julianday('now'))))",
            assetID,
          ),
          sql(c.env, "UPDATE grants SET active=1 WHERE asset_id=?", assetID),
          sql(
            c.env,
            "UPDATE audio_assets SET state='published' WHERE id=?",
            assetID,
          ),
          sql(
            c.env,
            "UPDATE publications SET state='published' WHERE audio_asset_id=?",
            assetID,
          ),
        );
      }
      statements.push(
        sql(c.env, "UPDATE sermons SET state='published' WHERE id=?", s.id),
        sql(
          c.env,
          "UPDATE publications SET state='published' WHERE sermon_id=? AND audio_asset_id IS NULL AND state IN ('removed','disputed')",
          s.id,
        ),
      );
    } else fail(400, "invalid_request", "Choose dispute, remove, or restore.");
    if (affected)
      statements.push(
        event(
          c,
          affected,
          "moderation" + action[0].toUpperCase() + action.slice(1),
          targetID,
        ),
      );
  }
  statements.push(
    auditStatement(c, actionID, type, targetID, action, reason, affected),
  );
  return command(c, { ok: true, actionID }, statements);
}
export async function claimSermon(
  c: Context,
  churchID: string,
  sermonID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  fields(c.body, ["reason"], ["reason"]);
  const reason = str(c.body.reason, 3000)!;
  const s = await one(
    c.env,
    "SELECT church_id FROM sermons WHERE id=?",
    sermonID,
  );
  if (s.church_id && s.church_id !== churchID)
    fail(
      409,
      "conflict",
      "A moderator must resolve attribution to another church.",
    );
  return command(c, { ok: true, sermonID }, [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM sermons WHERE id=? AND (church_id IS NULL OR church_id=?))",
      sermonID,
      churchID,
    ),
    sql(
      c.env,
      "UPDATE sermons SET church_id=?,church_verified=1 WHERE id=?",
      churchID,
      sermonID,
    ),
    auditStatement(c, uid(), "sermon", sermonID, "claim", reason, null),
  ]);
}
export async function moderatorCorrection(
  c: Context,
  sermonID: string,
): Promise<Response> {
  await requireRole(c, "moderator");
  fields(
    c.body,
    [
      "churchID",
      "title",
      "preacher",
      "primaryPassage",
      "serviceDate",
      "reason",
    ],
    ["reason"],
  );
  const reason = str(c.body.reason, 3000)!,
    s = await one(c.env, "SELECT * FROM sermons WHERE id=?", sermonID);
  const churchID =
    c.body.churchID === undefined
      ? s.church_id
      : str(c.body.churchID, 100, true);
  if (churchID)
    await one(c.env, "SELECT id FROM churches WHERE id=?", churchID);
  const set = [
      "church_id=?",
      "church_verified=CASE WHEN EXISTS(SELECT 1 FROM churches WHERE id=? AND verified=1) THEN 1 ELSE 0 END",
    ],
    args: unknown[] = [churchID, churchID];
  for (const [name, column] of [
    ["title", "title"],
    ["preacher", "preacher"],
    ["primaryPassage", "primary_passage"],
    ["serviceDate", "service_date"],
  ])
    if (c.body[name] !== undefined) {
      const value =
        name === "serviceDate" ? date(c.body[name]) : str(c.body[name], 200)!;
      set.push(`${column}=?`);
      args.push(value);
      if (name === "title" || name === "primaryPassage") {
        set.push(
          `${name === "title" ? "title_normalized" : "passage_normalized"}=?`,
        );
        args.push(normalized(value));
      }
    }
  const statements: Statement[] = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM sermons WHERE id=? AND church_id IS ?)",
      sermonID,
      s.church_id,
    ),
    sql(
      c.env,
      `UPDATE sermons SET ${set.join(",")} WHERE id=?`,
      ...args,
      sermonID,
    ),
  ];
  if (churchID !== s.church_id && s.canonical_audio_id)
    statements.push(...removalStatements(c.env, sermonID, "disputed"));
  statements.push(
    auditStatement(c, uid(), "sermon", sermonID, "correct", reason, null),
  );
  return command(c, { ok: true, sermonID }, statements);
}
export async function churchProfile(
  c: Context,
  churchID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  fields(c.body, [
    "name",
    "city",
    "region",
    "country",
    "website",
    "creditPolicy",
  ]);
  const set: string[] = [],
    args: unknown[] = [];
  for (const [name, column] of [
    ["name", "name"],
    ["city", "city"],
    ["region", "region"],
    ["country", "country"],
    ["website", "website"],
    ["creditPolicy", "credit_policy"],
  ])
    if (c.body[name] !== undefined) {
      set.push(`${column}=?`);
      args.push(
        name === "website"
          ? website(c.body[name])
          : name === "creditPolicy"
            ? choice(c.body[name], ["named", "anonymous"])
            : str(c.body[name], 150, name !== "name"),
      );
    }
  return command(
    c,
    { ok: true, churchID },
    set.length
      ? [
          sql(
            c.env,
            `UPDATE churches SET ${set.join(",")} WHERE id=?`,
            ...args,
            churchID,
          ),
        ]
      : [],
  );
}
export async function correction(
  c: Context,
  churchID: string,
  sermonID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  const sermon = await one(
    c.env,
    "SELECT * FROM sermons WHERE id=? AND church_id=?",
    sermonID,
    churchID,
  );
  fields(c.body, ["title", "preacher", "primaryPassage", "serviceDate"]);
  const set = ["church_verified=1"],
    args: unknown[] = [];
  for (const [name, column] of [
    ["title", "title"],
    ["preacher", "preacher"],
    ["primaryPassage", "primary_passage"],
    ["serviceDate", "service_date"],
  ])
    if (c.body[name] !== undefined) {
      const value =
        name === "serviceDate" ? date(c.body[name]) : str(c.body[name], 200);
      set.push(`${column}=?`);
      args.push(value);
      if (name === "title" || name === "primaryPassage") {
        set.push(
          `${name === "title" ? "title_normalized" : "passage_normalized"}=?`,
        );
        args.push(normalized(value!));
      }
    }
  return command(c, { ok: true, sermonID }, [
    sql(
      c.env,
      `UPDATE sermons SET ${set.join(",")} WHERE id=? AND church_id=?`,
      ...args,
      sermonID,
      churchID,
    ),
    auditStatement(
      c,
      uid(),
      "sermon",
      sermonID,
      "correct",
      "Church corrected public attribution",
      null,
    ),
  ]);
}
export async function churchDecision(
  c: Context,
  churchID: string,
  pubID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  fields(c.body, ["decision", "reason"], ["decision", "reason"]);
  const decision = choice(c.body.decision, ["approve", "reject"]),
    reason = str(c.body.reason, 3000)!;
  const p = await publicationRow(c.env, pubID);
  if (p.church_id !== churchID)
    fail(403, "forbidden", "This publication belongs to a different church.");
  const statements =
    decision === "approve"
      ? approvalStatements(c, p)
      : [
          guard(
            c.env,
            "EXISTS(SELECT 1 FROM publications WHERE id=? AND state='pendingRights')",
            pubID,
          ),
          sql(
            c.env,
            "UPDATE publications SET state='rejected' WHERE id=?",
            pubID,
          ),
          sql(
            c.env,
            "UPDATE audio_assets SET state='rejected' WHERE id=?",
            p.audio_asset_id,
          ),
        ];
  if (p.account_id)
    statements.push(event(c, p.account_id, "churchDecision", pubID));
  statements.push(
    auditStatement(
      c,
      uid(),
      "publication",
      pubID,
      decision,
      reason,
      p.account_id,
    ),
  );
  return command(c, { ok: true, publicationID: pubID }, statements);
}
export async function churchRemoval(
  c: Context,
  churchID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  fields(c.body, ["sermonID", "reason"], ["sermonID", "reason"]);
  const sermonID = str(c.body.sermonID, 100)!,
    reason = str(c.body.reason, 3000)!;
  await one(
    c.env,
    "SELECT id FROM sermons WHERE id=? AND church_id=?",
    sermonID,
    churchID,
  );
  const requestID = uid();
  return command(c, { ok: true, requestID }, [
    ...removalStatements(c.env, sermonID, "removed"),
    sql(
      c.env,
      "INSERT INTO removals(id,church_id,sermon_id,account_id,reason,created_at) VALUES(?,?,?,?,?,?)",
      requestID,
      churchID,
      sermonID,
      c.account.id,
      reason,
      now(),
    ),
    auditStatement(c, uid(), "sermon", sermonID, "remove", reason, null),
  ]);
}
export function serviceView(r: Row): Row {
  return {
    id: r.id,
    service: r.service,
    startsAt: r.starts_at,
    expiresAt: r.expires_at,
    recordingAllowed: !!r.recording_allowed,
    publicSharingAllowed: !!r.public_sharing_allowed,
    reviewRequired: !!r.review_required,
    revoked: !!r.revoked,
    token: r.token,
  };
}
export async function issueService(
  c: Context,
  churchID: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  const b = c.body;
  fields(
    b,
    [
      "service",
      "startsAt",
      "recordingAllowed",
      "publicSharingAllowed",
      "reviewRequired",
      "expiresAt",
    ],
    [
      "service",
      "startsAt",
      "recordingAllowed",
      "publicSharingAllowed",
      "reviewRequired",
      "expiresAt",
    ],
  );
  const service = str(b.service, 150)!,
    startsAt = date(b.startsAt),
    expiresAt = date(b.expiresAt);
  for (const field of [
    "recordingAllowed",
    "publicSharingAllowed",
    "reviewRequired",
  ])
    bool(b[field]);
  if (
    Date.parse(expiresAt) <= Date.now() ||
    Date.parse(expiresAt) <= Date.parse(startsAt) ||
    Date.parse(expiresAt) > Date.now() + 366 * 86400000
  )
    fail(
      400,
      "invalid_request",
      "Service permission must expire after the service within one year.",
    );
  const serviceID = uid();
  const token = await signToken(c.env, "service+jwt", {
    id: serviceID,
    church: churchID,
    service,
    startsAt,
    recordingAllowed: b.recordingAllowed,
    publicSharingAllowed: b.publicSharingAllowed,
    reviewRequired: b.reviewRequired,
    expiresAt,
    exp: Math.floor(Date.parse(expiresAt) / 1000),
  });
  return command(
    c,
    {
      serviceID,
      token,
      printURL: `${c.env.PUBLIC_BASE_URL}/portal/services/${serviceID}/print`,
    },
    [
      sql(
        c.env,
        "INSERT INTO services(id,church_id,service,starts_at,recording_allowed,public_sharing_allowed,review_required,expires_at,token) VALUES(?,?,?,?,?,?,?,?,?)",
        serviceID,
        churchID,
        service,
        startsAt,
        b.recordingAllowed ? 1 : 0,
        b.publicSharingAllowed ? 1 : 0,
        b.reviewRequired ? 1 : 0,
        expiresAt,
        token,
      ),
      auditStatement(
        c,
        uid(),
        "service",
        serviceID,
        "issue",
        "Church issued service permission",
        null,
      ),
    ],
  );
}
export async function revokeService(
  c: Context,
  churchID: string,
  id: string,
): Promise<Response> {
  await requireRole(c, "staff", churchID);
  noBody(c);
  await one(
    c.env,
    "SELECT id FROM services WHERE id=? AND church_id=?",
    id,
    churchID,
  );
  return command(c, { ok: true }, [
    sql(
      c.env,
      "UPDATE services SET revoked=1 WHERE id=? AND church_id=?",
      id,
      churchID,
    ),
    sql(c.env, "UPDATE grants SET active=0 WHERE service_id=?", id),
    auditStatement(
      c,
      uid(),
      "service",
      id,
      "revoke",
      "Church revoked service permission",
      null,
    ),
  ]);
}
