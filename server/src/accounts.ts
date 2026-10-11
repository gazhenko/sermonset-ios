import type { Context, Env, Row, Statement } from "./types";
import {
  bool,
  command,
  fail,
  fields,
  guard,
  json,
  noBody,
  now,
  one,
  page,
  rows,
  sha,
  sql,
  str,
  uid,
} from "./common";
import { constantEqual, profile } from "./security";
export async function updateProfile(c: Context): Promise<Response> {
  const b = c.body;
  fields(b, [
    "displayName",
    "avatarStyle",
    "journeyOptIn",
    "journeyCity",
    "hidePastJourneys",
    "creditOptIn",
  ]);
  const set: string[] = [],
    args: unknown[] = [];
  for (const [name, column, max] of [
    ["displayName", "display_name", 80],
    ["avatarStyle", "avatar_style", 40],
    ["journeyCity", "journey_city", 120],
  ] as const) {
    if (b[name] !== undefined) {
      set.push(`${column}=?`);
      args.push(str(b[name], max, name !== "avatarStyle"));
    }
  }
  if (b.journeyOptIn !== undefined) {
    set.push("journey_opt_in=?");
    args.push(bool(b.journeyOptIn) ? 1 : 0);
  }
  if (b.creditOptIn !== undefined) {
    set.push("credit_opt_in=?");
    args.push(bool(b.creditOptIn) ? 1 : 0);
  }
  if (b.hidePastJourneys !== undefined) bool(b.hidePastJourneys);
  const stmts: Statement[] = [];
  if (set.length)
    stmts.push(
      sql(
        c.env,
        `UPDATE accounts SET ${set.join(",")} WHERE id=?`,
        ...args,
        c.account.id,
      ),
    );
  if (b.hidePastJourneys === true)
    stmts.push(
      sql(
        c.env,
        "UPDATE journey_events SET hidden=1 WHERE participant_id=?",
        c.account.id,
      ),
    );
  return command(c, { ok: true, accountID: c.account.id }, stmts);
}
export async function linkCode(c: Context): Promise<Response> {
  noBody(c);
  if (c.session)
    fail(403, "forbidden", "Issue browser codes from the signed-in app.");
  const code = [...crypto.getRandomValues(new Uint8Array(10))]
    .map((b) => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[b & 31])
    .join("");
  const expires = Math.floor(Date.now() / 1000) + 300;
  return command(
    c,
    { code, expiresAt: new Date(expires * 1000).toISOString() },
    [
      sql(
        c.env,
        "INSERT INTO link_codes(hash,account_id,expires) VALUES(?,?,?)",
        await sha(code),
        c.account.id,
        expires,
      ),
    ],
  );
}
export async function webSession(
  request: Request,
  env: Env,
  body: Row,
): Promise<Response> {
  fields(body, ["code", "bootstrapSecret", "accountID"]);
  if (request.headers.get("origin") !== new URL(env.PUBLIC_BASE_URL).origin)
    fail(403, "forbidden", "Open the console on its configured origin.");
  let account: Row;
  const statements: Statement[] = [];
  if (body.code !== undefined) {
    fields(body, ["code"], ["code"]);
    const code = str(body.code, 30)!;
    const codeHash = await sha(code);
    const found = await sql(
      env,
      "SELECT * FROM link_codes WHERE hash=? AND expires>?",
      codeHash,
      Math.floor(Date.now() / 1000),
    ).first();
    if (!found)
      fail(
        401,
        "unauthorized",
        "This browser code expired or was already used.",
      );
    account = await one(
      env,
      "SELECT * FROM accounts WHERE id=?",
      found.account_id,
    );
    statements.push(
      guard(
        env,
        "EXISTS(SELECT 1 FROM link_codes WHERE hash=? AND expires>CAST(strftime('%s','now') AS INTEGER))",
        codeHash,
      ),
      sql(env, "DELETE FROM link_codes WHERE hash=?", codeHash),
    );
  } else {
    fields(
      body,
      ["bootstrapSecret", "accountID"],
      ["bootstrapSecret", "accountID"],
    );
    str(body.bootstrapSecret, 200);
    str(body.accountID, 100);
    if (
      !env.ADMIN_BOOTSTRAP_SECRET ||
      env.ADMIN_BOOTSTRAP_SECRET.length < 32 ||
      !(await constantEqual(body.bootstrapSecret, env.ADMIN_BOOTSTRAP_SECRET))
    )
      fail(401, "unauthorized", "The bootstrap secret is invalid.");
    account = await one(
      env,
      "SELECT * FROM accounts WHERE id=?",
      body.accountID,
    );
    statements.push(
      sql(
        env,
        "INSERT OR IGNORE INTO roles(account_id,role) VALUES(?,'admin')",
        account.id,
      ),
    );
  }
  if (account.banned) fail(403, "forbidden", "This account is restricted.");
  const token = uid() + uid(),
    csrf = uid() + uid(),
    expires = Math.floor(Date.now() / 1000) + 28800;
  statements.push(
    sql(
      env,
      "INSERT INTO sessions(hash,account_id,csrf,expires) VALUES(?,?,?,?)",
      await sha(token),
      account.id,
      csrf,
      expires,
    ),
    sql(env, "DELETE FROM mutation_guard"),
  );
  try {
    await env.DB.batch(statements);
  } catch {
    fail(401, "unauthorized", "This browser code was already used.");
  }
  return json(
    {
      account: await profile(env, account),
      csrfToken: csrf,
      expiresAt: new Date(expires * 1000).toISOString(),
    },
    200,
    {
      "set-cookie": `community_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800${new URL(env.PUBLIC_BASE_URL).protocol === "https:" ? "; Secure" : ""}`,
    },
  );
}
export async function logout(c: Context): Promise<Response> {
  noBody(c);
  const stmts = c.session
    ? [sql(c.env, "DELETE FROM sessions WHERE hash=?", c.session.hash)]
    : [];
  const response = await command(c, { ok: true }, stmts);
  response.headers.set(
    "set-cookie",
    "community_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0" +
      (new URL(c.env.PUBLIC_BASE_URL).protocol === "https:" ? "; Secure" : ""),
  );
  return response;
}
export async function blockAccount(c: Context, id?: string): Promise<Response> {
  if (id) {
    noBody(c);
    return command(c, { ok: true }, [
      sql(
        c.env,
        "DELETE FROM blocks WHERE account_id=? AND blocked_id=?",
        c.account.id,
        id,
      ),
    ]);
  }
  fields(c.body, ["accountID"], ["accountID"]);
  id = str(c.body.accountID, 100)!;
  if (id === c.account.id)
    fail(400, "invalid_request", "Choose another account.");
  await one(c.env, "SELECT id FROM accounts WHERE id=?", id);
  return command(c, { ok: true }, [
    sql(
      c.env,
      "INSERT OR IGNORE INTO blocks(account_id,blocked_id) VALUES(?,?)",
      c.account.id,
      id,
    ),
    sql(
      c.env,
      "UPDATE offers SET state='cancelled' WHERE state IN ('open','proposed') AND ((sender_id=? AND recipient_id=?) OR (sender_id=? AND recipient_id=?))",
      c.account.id,
      id,
      id,
      c.account.id,
    ),
  ]);
}
export async function cleanupDeletedObjects(env: Env): Promise<void> {
  for (const job of await rows(env, "SELECT * FROM deletion_jobs LIMIT 100")) {
    await (job.bucket === "AUDIO" ? env.AUDIO : env.IMAGES).delete(
      job.storage_key,
    );
    await sql(
      env,
      "DELETE FROM deletion_jobs WHERE bucket=? AND storage_key=?",
      job.bucket,
      job.storage_key,
    ).run();
  }
}
export async function deleteAccount(c: Context): Promise<Response> {
  noBody(c);
  const id = c.account.id;
  await c.env.DB.batch([
    sql(
      c.env,
      "INSERT OR IGNORE INTO deletion_jobs(bucket,storage_key) SELECT 'AUDIO',storage_key FROM audio_assets WHERE owner_id=?",
      id,
    ),
    sql(
      c.env,
      "INSERT OR IGNORE INTO deletion_jobs(bucket,storage_key) SELECT 'IMAGES',storage_key FROM shares WHERE account_id=?",
      id,
    ),
    sql(
      c.env,
      "UPDATE sermons SET state='removed' WHERE canonical_audio_id IN (SELECT id FROM audio_assets WHERE owner_id=?)",
      id,
    ),
    sql(
      c.env,
      "UPDATE grants SET active=0 WHERE asset_id IN (SELECT id FROM audio_assets WHERE owner_id=?)",
      id,
    ),
    sql(c.env, "UPDATE audio_assets SET state='removed' WHERE owner_id=?", id),
    sql(
      c.env,
      "UPDATE publications SET state='removed' WHERE account_id=?",
      id,
    ),
    sql(c.env, "DELETE FROM shares WHERE account_id=?", id),
    sql(c.env, "DELETE FROM reports WHERE reporter_id=?", id),
    sql(
      c.env,
      "UPDATE audit SET reason='Account deleted' WHERE actor_id=? OR affected_account_id=?",
      id,
      id,
    ),
    sql(c.env, "DELETE FROM nonces WHERE account_id=?", id),
    sql(
      c.env,
      "DELETE FROM nonces WHERE account_id=?",
      "registration:" + c.account.key_fingerprint,
    ),
    sql(c.env, "DELETE FROM accounts WHERE id=?", id),
  ]);
  await cleanupDeletedObjects(c.env);
  return json({ ok: true });
}
