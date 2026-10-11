import type { Context, Env, Row, Statement } from "./types";
export class APIError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}
export function fail(status: number, code: string, message: string): never {
  throw new APIError(status, code, message);
}
export const now = () => new Date().toISOString();
export const uid = () => crypto.randomUUID();
export const encoder = new TextEncoder();
export function b64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
export function unb64(s: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(s))
    fail(400, "invalid_request", "Invalid encoded value.");
  try {
    return Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) =>
      c.charCodeAt(0),
    );
  } catch {
    fail(400, "invalid_request", "Invalid encoded value.");
  }
}
export async function sha(data: Uint8Array | string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        typeof data === "string" ? encoder.encode(data) : data,
      ),
    ),
  ]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export const sql = (env: Env, query: string, ...args: unknown[]) =>
  env.DB.prepare(query).bind(...args);
export async function one(
  env: Env,
  query: string,
  ...args: unknown[]
): Promise<Row> {
  const row = await sql(env, query, ...args).first();
  if (!row) fail(404, "not_found", "This item could not be found.");
  return row;
}
export const rows = async (env: Env, query: string, ...args: unknown[]) =>
  (await sql(env, query, ...args).all()).results;
export function json(
  value: unknown,
  status = 200,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "API-Version": "1",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...extra,
    },
  });
}
export function fields(
  body: Row,
  allowed: string[],
  required: string[] = [],
): void {
  if (!body || typeof body !== "object" || Array.isArray(body))
    fail(400, "invalid_request", "A JSON object is required.");
  if (
    Object.keys(body).some((k) => !allowed.includes(k)) ||
    required.some((k) => body[k] === undefined)
  )
    fail(400, "invalid_request", "Unexpected or missing fields.");
}
export function str(
  value: unknown,
  max = 300,
  nullable = false,
): string | null {
  if (nullable && value === null) return null;
  if (
    typeof value !== "string" ||
    value.length > max ||
    (!nullable && !value.trim()) ||
    /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)
  )
    fail(400, "invalid_request", "A valid text value is required.");
  return value;
}
export function num(
  value: unknown,
  min = 0,
  max = Number.MAX_SAFE_INTEGER,
  integer = false,
): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < min ||
    value > max ||
    (integer && !Number.isInteger(value))
  )
    fail(400, "invalid_request", "A valid number is required.");
  return value;
}
export function bool(value: unknown): boolean {
  if (typeof value !== "boolean")
    fail(400, "invalid_request", "A boolean value is required.");
  return value;
}
export function choice<T extends string>(
  value: unknown,
  values: readonly T[],
): T {
  if (typeof value !== "string" || !values.includes(value as T))
    fail(400, "invalid_request", "Unsupported option.");
  return value as T;
}
export function date(value: unknown): string {
  const s = str(value, 40)!;
  if (!/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(s) || !Number.isFinite(Date.parse(s)))
    fail(400, "invalid_request", "A valid ISO date is required.");
  return new Date(s).toISOString();
}
export function checksum(value: unknown): string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value))
    fail(400, "invalid_request", "A lowercase SHA-256 checksum is required.");
  return value;
}
export function website(value: unknown): string {
  const s = str(value, 1000)!;
  try {
    if (new URL(s).protocol !== "https:") throw 0;
  } catch {
    fail(400, "invalid_request", "An HTTPS website is required.");
  }
  return s;
}
export const normalized = (s: string) =>
  s
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, "");
export function pagination(url: URL): { limit: number; offset: number } {
  let offset = 0;
  const cursor = url.searchParams.get("cursor");
  if (cursor) {
    const s = new TextDecoder().decode(unb64(cursor));
    if (!/^\d+$/.test(s)) fail(400, "invalid_request", "Invalid cursor.");
    offset = Number(s);
  }
  const limit = Number(url.searchParams.get("limit") ?? 20);
  if (
    !Number.isSafeInteger(offset) ||
    offset > 1000000 ||
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > 100
  )
    fail(400, "invalid_request", "Invalid page limits.");
  return { limit, offset };
}
export async function page(
  c: Pick<Context, "url" | "env">,
  query: string,
  args: unknown[] = [],
  project: (row: Row) => unknown = (r) => r,
): Promise<Response> {
  const { limit, offset } = pagination(c.url);
  const result = await rows(
    c.env,
    `${query} LIMIT ? OFFSET ?`,
    ...args,
    limit + 1,
    offset,
  );
  return json({
    items: result.slice(0, limit).map(project),
    nextCursor:
      result.length > limit
        ? b64(encoder.encode(String(offset + limit)))
        : null,
  });
}
export function guard(env: Env, query: string, ...args: unknown[]): Statement {
  return sql(
    env,
    `INSERT INTO mutation_guard(ok) SELECT CASE WHEN (${query}) THEN 1 ELSE 0 END`,
    ...args,
  );
}
export function event(
  c: Context,
  accountID: string,
  type: string,
  resourceID: string,
): Statement {
  return sql(
    c.env,
    // Keep actor filtering at the write boundary for every request notification.
    "INSERT INTO inbox(id,account_id,type,resource_id,created_at) SELECT ?,?,?,?,? WHERE ?<>?",
    uid(),
    accountID,
    type,
    resourceID,
    now(),
    accountID,
    c.account.id,
  );
}
export function mapDBError(error: unknown): never {
  const s = error instanceof Error ? error.message : "";
  for (const [code, status, message] of [
    ["stale_version", 409, "The card changed owner. Refresh and try again."],
    ["expired", 410, "This offer has expired."],
    ["blocked", 403, "This interaction is blocked."],
    ["forbidden", 403, "This account cannot perform this action."],
    ["invalid_recipient", 409, "Choose a different recipient."],
    ["conflict", 409, "This item has already changed."],
    [
      "mutation_guard",
      409,
      "This item has already changed. Refresh and try again.",
    ],
    ["UNIQUE constraint", 409, "This item already exists."],
  ] as const) {
    if (s.includes(code))
      fail(
        status,
        code === "mutation_guard" || code === "UNIQUE constraint"
          ? "conflict"
          : code,
        message,
      );
  }
  throw error;
}
export async function replay(c: Context): Promise<Row | null> {
  const found = await sql(
    c.env,
    "SELECT hash,response FROM commands WHERE account_id=? AND key=?",
    c.account.id,
    c.key,
  ).first();
  if (!found) return null;
  if (found.hash !== c.hash)
    fail(
      409,
      "idempotency_conflict",
      "Use a new idempotency key for a different request.",
    );
  return JSON.parse(found.response);
}
export async function command(
  c: Context,
  response: Row,
  statements: Statement[],
  responseSQL?: { query: string; args: unknown[] },
): Promise<Response> {
  const cached = await replay(c);
  if (cached) return json(cached);
  try {
    const batch = [
      sql(
        c.env,
        "INSERT INTO commands(account_id,key,hash,response,created_at) VALUES(?,?,?,?,?)",
        c.account.id,
        c.key,
        c.hash,
        JSON.stringify(response),
        now(),
      ),
      ...statements,
      sql(c.env, "DELETE FROM mutation_guard"),
    ];
    if (responseSQL)
      batch.push(
        sql(
          c.env,
          `UPDATE commands SET response=(${responseSQL.query}) WHERE account_id=? AND key=?`,
          ...responseSQL.args,
          c.account.id,
          c.key,
        ),
      );
    await c.env.DB.batch(batch);
  } catch (e) {
    const cached = await replay(c);
    if (cached) return json(cached);
    mapDBError(e);
  }
  return json((await replay(c))!);
}
export const noBody = (c: Context) => fields(c.body, []);
