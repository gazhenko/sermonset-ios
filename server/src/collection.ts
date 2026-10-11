import type { Context, Env, Row, Statement } from "./types";
import {
  command,
  fail,
  fields,
  guard,
  json,
  noBody,
  now,
  one,
  rows,
  sha,
  sql,
  str,
  uid,
  choice,
} from "./common";
import { authorizedSQL } from "./projections";
export function mint(
  env: Env,
  cardID: string,
  accountID: string,
  sermonID: string,
  source: string,
): Statement[] {
  const editionID = sermonID + ":" + `edition`;
  return [
    sql(
      env,
      `INSERT OR IGNORE INTO editions(id,sermon_id,type) SELECT ? || ':' || CASE WHEN EXISTS(SELECT 1 FROM audio_assets a JOIN grants g ON g.asset_id=a.id WHERE a.id=s.canonical_audio_id AND a.kind='official' AND ${authorizedSQL}) THEN 'Church' ELSE 'Community' END,id,
 CASE WHEN EXISTS(SELECT 1 FROM audio_assets a JOIN grants g ON g.asset_id=a.id WHERE a.id=s.canonical_audio_id AND a.kind='official' AND ${authorizedSQL}) THEN 'Church' ELSE 'Community' END FROM sermons s WHERE s.id=?`,
      editionID,
      sermonID,
    ),
    sql(
      env,
      `INSERT INTO cards(id,edition_id,owner_id,serial_number,version,source,created_at) SELECT ?,id,?,next_serial+1,1,?,? FROM editions WHERE sermon_id=? ORDER BY CASE type WHEN 'Church' THEN 0 ELSE 1 END LIMIT 1`,
      cardID,
      accountID,
      source,
      now(),
      sermonID,
    ),
  ];
}
export async function keep(c: Context, id: string): Promise<Response> {
  fields(c.body, ["source"], ["source"]);
  const source = choice(c.body.source, ["discover", "shared"]);
  await one(
    c.env,
    "SELECT id FROM sermons WHERE id=? AND state='published'",
    id,
  );
  const existing = await sql(
    c.env,
    "SELECT card_id FROM keep_mints WHERE account_id=? AND sermon_id=?",
    c.account.id,
    id,
  ).first();
  if (existing) return command(c, { ok: true, cardID: existing.card_id }, []);
  const cardID = uid();
  const statements = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM sermons WHERE id=? AND state='published')",
      id,
    ),
    ...mint(c.env, cardID, c.account.id, id, source),
    sql(
      c.env,
      "INSERT INTO keep_mints(account_id,sermon_id,card_id) VALUES(?,?,?)",
      c.account.id,
      id,
      cardID,
    ),
  ];
  try {
    return await command(c, { ok: true, cardID }, statements);
  } catch (e) {
    const raced = await sql(
      c.env,
      "SELECT card_id FROM keep_mints WHERE account_id=? AND sermon_id=?",
      c.account.id,
      id,
    ).first();
    if (raced) return command(c, { ok: true, cardID: raced.card_id }, []);
    throw e;
  }
}
export function isoWeek(date = new Date()): string {
  const d = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const year = d.getUTCFullYear();
  const start = new Date(Date.UTC(year, 0, 1));
  return `${year}-W${String(Math.ceil(((d.getTime() - start.getTime()) / 86400000 + 1) / 7)).padStart(2, "0")}`;
}
export function season(date = new Date()): string {
  const y = date.getUTCFullYear();
  const a = y % 19,
    b = Math.floor(y / 100),
    c = y % 100,
    d = Math.floor(b / 4),
    e = b % 4,
    f = Math.floor((b + 8) / 25),
    g = Math.floor((b - f + 1) / 3),
    h = (19 * a + b - d - g + 15) % 30,
    i = Math.floor(c / 4),
    k = c % 4,
    l = (32 + 2 * e + 2 * i - h - k) % 7,
    m = Math.floor((a + 11 * h + 22 * l) / 451),
    month = Math.floor((h + l - 7 * m + 114) / 31),
    day = ((h + l - 7 * m + 114) % 31) + 1;
  const easter = Date.UTC(y, month - 1, day),
    t = Date.UTC(y, date.getUTCMonth(), date.getUTCDate());
  const christmas = Date.UTC(y, 11, 25);
  const advent = new Date(Date.UTC(y, 11, 24));
  advent.setUTCDate(advent.getUTCDate() - advent.getUTCDay() - 21);
  if (t >= advent.getTime() && t < christmas) return "Advent";
  if (t >= christmas || (date.getUTCMonth() === 0 && date.getUTCDate() <= 6))
    return "Christmas";
  if (t >= easter - 46 * 86400000 && t < easter) return "Lent";
  if (t >= easter && t < easter + 50 * 86400000) return "Easter";
  return "Ordinary time";
}
export async function buildPool(env: Env, week = isoWeek()): Promise<Row> {
  const sermons = await rows(
    env,
    "SELECT id,church_id,themes,city FROM sermons WHERE state='published' ORDER BY created_at DESC,id LIMIT 500",
  );
  const chosen: Row[] = [];
  const counts = new Map<string, number>();
  while (sermons.length) {
    sermons.sort(
      (a, b) =>
        (counts.get("church:" + a.church_id) ?? 0) +
        (counts.get("theme:" + JSON.parse(a.themes)[0]) ?? 0) -
        ((counts.get("church:" + b.church_id) ?? 0) +
          (counts.get("theme:" + JSON.parse(b.themes)[0]) ?? 0)),
    );
    const item = sermons.shift()!;
    chosen.push(item);
    for (const key of [
      "church:" + item.church_id,
      "theme:" + JSON.parse(item.themes)[0],
    ])
      counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const pool = {
    week,
    season: season(),
    sermon_ids: JSON.stringify(chosen.map((s) => s.id)),
  };
  await sql(
    env,
    "INSERT OR IGNORE INTO pack_pools(week,season,sermon_ids,created_at) VALUES(?,?,?,?)",
    week,
    pool.season,
    pool.sermon_ids,
    now(),
  ).run();
  return one(env, "SELECT * FROM pack_pools WHERE week=?", week);
}
export async function getPack(c: Context): Promise<Row> {
  const week = isoWeek();
  const existing = await sql(
    c.env,
    "SELECT * FROM packs WHERE account_id=? AND week=?",
    c.account.id,
    week,
  ).first();
  if (existing) return existing;
  const pool = await buildPool(c.env, week);
  const owned = new Set(
    (
      await rows(
        c.env,
        "SELECT sermon_id FROM history WHERE account_id=?",
        c.account.id,
      )
    ).map((r) => r.sermon_id),
  );
  const catalog = new Map(
    (
      await rows(
        c.env,
        "SELECT id,church_id,city,themes FROM sermons WHERE state='published'",
      )
    ).map((r) => [r.id, r]),
  );
  const candidates: string[] = JSON.parse(pool.sermon_ids).filter(
    (id: string) => !owned.has(id) && catalog.has(id),
  );
  const ranked = await Promise.all(
    candidates.map(async (id) => ({
      id,
      rank: await sha(`${c.account.id}\n${week}\n${id}`),
    })),
  );
  ranked.sort((a, b) => a.rank.localeCompare(b.rank));
  // Locality comes from public library venues, never the listener's location.
  const libraryCities = new Set(
    (
      await rows(
        c.env,
        "SELECT DISTINCT s.city FROM history h JOIN sermons s ON s.id=h.sermon_id WHERE h.account_id=? AND s.city IS NOT NULL",
        c.account.id,
      )
    ).map((r) => r.city),
  );
  const chosen: string[] = [],
    churchCounts = new Map<string, number>(),
    themeCounts = new Map<string, number>();
  function take(items: typeof ranked): boolean {
    if (!items.length) return false;
    const score = (id: string) => {
      const item = catalog.get(id)!;
      return (
        (churchCounts.get(item.church_id) ?? 0) * 3 +
        JSON.parse(item.themes).reduce(
          (sum: number, theme: string) => sum + (themeCounts.get(theme) ?? 0),
          0,
        )
      );
    };
    items.sort(
      (a, b) => score(a.id) - score(b.id) || a.rank.localeCompare(b.rank),
    );
    const selected = items[0].id;
    chosen.push(selected);
    const item = catalog.get(selected)!;
    churchCounts.set(
      item.church_id,
      (churchCounts.get(item.church_id) ?? 0) + 1,
    );
    for (const theme of JSON.parse(item.themes))
      themeCounts.set(theme, (themeCounts.get(theme) ?? 0) + 1);
    return true;
  }
  for (let i = 0; i < 2; i++)
    take(
      ranked.filter(
        (r) =>
          !chosen.includes(r.id) && libraryCities.has(catalog.get(r.id)!.city),
      ),
    );
  if (chosen.length < 5)
    take(
      ranked.filter(
        (r) =>
          !chosen.includes(r.id) && !libraryCities.has(catalog.get(r.id)!.city),
      ),
    );
  while (
    chosen.length < 5 &&
    take(ranked.filter((r) => !chosen.includes(r.id)))
  ) {}
  await sql(
    c.env,
    "INSERT OR IGNORE INTO packs(account_id,week,season,sermon_ids,fallback) VALUES(?,?,?,?,?)",
    c.account.id,
    week,
    pool.season,
    JSON.stringify(chosen),
    chosen.length < 5 ? 1 : 0,
  ).run();
  return one(
    c.env,
    "SELECT * FROM packs WHERE account_id=? AND week=?",
    c.account.id,
    week,
  );
}
export const packView = (p: Row) => ({
  week: p.week,
  season: p.season,
  sermonIDs: JSON.parse(p.sermon_ids),
  opened: !!p.opened,
  fallback: !!p.fallback,
});
export async function openPack(c: Context, week: string): Promise<Response> {
  noBody(c);
  if (week !== isoWeek())
    fail(410, "expired", "Only the current weekly pack can be opened.");
  const pack = await getPack(c);
  if (pack.opened) return command(c, { ok: true, week }, []);
  const ids: string[] = JSON.parse(pack.sermon_ids);
  const stmts = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM packs WHERE account_id=? AND week=? AND opened=0)",
      c.account.id,
      week,
    ),
  ];
  for (const id of ids) {
    stmts.push(
      guard(
        c.env,
        "EXISTS(SELECT 1 FROM sermons WHERE id=? AND state='published')",
        id,
      ),
      ...mint(c.env, uid(), c.account.id, id, "pack"),
    );
  }
  stmts.push(
    sql(
      c.env,
      "UPDATE packs SET opened=1 WHERE account_id=? AND week=?",
      c.account.id,
      week,
    ),
  );
  try {
    return await command(c, { ok: true, week }, stmts);
  } catch (e) {
    const current = await one(
      c.env,
      "SELECT opened FROM packs WHERE account_id=? AND week=?",
      c.account.id,
      week,
    );
    if (current.opened) return command(c, { ok: true, week }, []);
    throw e;
  }
}
export const eligibleJourneySQL = `NOT EXISTS(SELECT 1 FROM journey_events e LEFT JOIN accounts a ON a.id=e.participant_id WHERE e.card_id=c.id AND (e.hidden=1 OR e.city IS NULL OR a.id IS NULL OR a.journey_opt_in=0))`;
export async function recomputeCohorts(env: Env): Promise<void> {
  await env.DB.batch([
    sql(env, "DELETE FROM journey_cohorts"),
    sql(
      env,
      `INSERT INTO journey_cohorts(city,cards) SELECT j.city,COUNT(DISTINCT j.card_id) FROM journey_events j JOIN cards c ON c.id=j.card_id WHERE ${eligibleJourneySQL} GROUP BY j.city`,
    ),
  ]);
}
export async function journey(env: Env, id: string): Promise<Row> {
  await one(env, "SELECT id FROM cards WHERE id=?", id);
  const eligible = await sql(
    env,
    `SELECT 1 FROM cards c WHERE c.id=? AND ${eligibleJourneySQL}`,
    id,
  ).first();
  if (!eligible) return { cardID: id, stops: [], suppressed: true };
  const events = await rows(
    env,
    "SELECT city,occurred_at FROM journey_events WHERE card_id=? ORDER BY id",
    id,
  );
  for (const e of events) {
    const cohort = await sql(
      env,
      `SELECT COUNT(DISTINCT j.card_id) AS count FROM journey_events j JOIN cards c ON c.id=j.card_id WHERE j.city=? AND ${eligibleJourneySQL}`,
      e.city,
    ).first();
    if ((cohort?.count ?? 0) < 3)
      return { cardID: id, stops: [], suppressed: true };
  }
  return {
    cardID: id,
    stops: events.map((e) => ({
      city: e.city,
      week: isoWeek(new Date(e.occurred_at)),
    })),
    suppressed: false,
  };
}
