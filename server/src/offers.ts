import type { Context, Env, Row, Statement } from "./types";
import {
  choice,
  command,
  date,
  event,
  fail,
  fields,
  guard,
  json,
  noBody,
  now,
  num,
  one,
  sql,
  str,
  uid,
} from "./common";
import { blocked, signToken, verifyToken } from "./security";
import { card, cardSelect, offer } from "./projections";
export async function createOffer(c: Context): Promise<Response> {
  fields(
    c.body,
    ["kind", "cardID", "cardVersion", "recipientID", "message", "expiresAt"],
    ["kind", "cardID", "cardVersion"],
  );
  const b = c.body;
  const kind = choice(b.kind, ["gift", "swap"]),
    cardID = str(b.cardID, 100)!,
    version = num(b.cardVersion, 1, 2147483647, true);
  const owned = await one(c.env, `${cardSelect} WHERE c.id=?`, cardID);
  if (owned.owner_id !== c.account.id || owned.version !== version)
    fail(409, "stale_version", "Refresh the binder before offering this card.");
  const recipientID =
    b.recipientID === undefined ? null : str(b.recipientID, 100, true);
  if (recipientID) {
    const recipient = await one(
      c.env,
      "SELECT id,banned FROM accounts WHERE id=?",
      recipientID,
    );
    if (recipientID === c.account.id || recipient.banned)
      fail(403, "forbidden", "Choose an available recipient.");
    if (await blocked(c.env, c.account.id, recipientID))
      fail(403, "blocked", "This interaction is blocked.");
  }
  const message = b.message === undefined ? null : str(b.message, 300, true);
  const expires =
    b.expiresAt === undefined
      ? new Date(Date.now() + 7 * 86400000).toISOString()
      : date(b.expiresAt);
  if (
    Date.parse(expires) <= Date.now() ||
    Date.parse(expires) > Date.now() + 7 * 86400000 + 1000
  )
    fail(400, "invalid_request", "Offers expire within seven days.");
  const id = uid(),
    token = await signToken(c.env, "offer+jwt", {
      offerID: id,
      cardID,
      senderID: c.account.id,
      exp: Math.floor(Date.parse(expires) / 1000),
    });
  const stmts = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM cards WHERE id=? AND owner_id=? AND version=?)",
      cardID,
      c.account.id,
      version,
    ),
    sql(
      c.env,
      "INSERT INTO offers(id,kind,sender_id,recipient_id,card_id,card_version,message,expires_at,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
      id,
      kind,
      c.account.id,
      recipientID,
      cardID,
      version,
      message,
      expires,
      now(),
    ),
  ];
  if (recipientID) stmts.push(event(c, recipientID, "offerReceived", id));
  return command(c, { offerID: id, token }, stmts);
}
async function access(c: Context, o: Row, token: unknown): Promise<void> {
  if (o.sender_id === c.account.id || o.recipient_id === c.account.id) return;
  if (o.recipient_id)
    fail(403, "forbidden", "This offer belongs to another recipient.");
  const payload = await verifyToken(c.env, token, "offer+jwt");
  if (
    payload.offerID !== o.id ||
    payload.cardID !== o.card_id ||
    payload.senderID !== o.sender_id
  )
    fail(403, "forbidden", "This token belongs to a different offer.");
}
async function interaction(c: Context, o: Row): Promise<void> {
  if (
    c.account.id !== o.sender_id &&
    (await blocked(c.env, c.account.id, o.sender_id))
  )
    fail(403, "blocked", "This interaction is blocked.");
  if (o.recipient_id && (await blocked(c.env, o.sender_id, o.recipient_id)))
    fail(403, "blocked", "This interaction is blocked.");
  const sender = await one(
    c.env,
    "SELECT banned FROM accounts WHERE id=?",
    o.sender_id,
  );
  if (sender.banned) fail(403, "forbidden", "This offer is unavailable.");
}
export async function preview(c: Context, id: string): Promise<Response> {
  const o = await one(c.env, "SELECT * FROM offers WHERE id=?", id);
  await interaction(c, o);
  await access(c, o, c.url.searchParams.get("token"));
  const sender = await one(
    c.env,
    "SELECT display_name FROM accounts WHERE id=?",
    o.sender_id,
  );
  return json({
    offer: offer(o),
    card: card(await one(c.env, `${cardSelect} WHERE c.id=?`, o.card_id)),
    senderDisplayName: sender.display_name,
  });
}
export async function transition(
  c: Context,
  id: string,
  action: string,
): Promise<Response> {
  const o = await one(c.env, "SELECT * FROM offers WHERE id=?", id);
  const b = c.body;
  if (["cancel", "confirm"].includes(action)) {
    noBody(c);
    if (o.sender_id !== c.account.id)
      fail(403, "forbidden", "Only the sender can do this.");
  } else {
    fields(
      b,
      action === "propose" ? ["token", "cardID", "cardVersion"] : ["token"],
      action === "propose" ? ["cardID", "cardVersion"] : [],
    );
    if (o.sender_id === c.account.id)
      fail(403, "forbidden", "The sender cannot receive their own offer.");
    await interaction(c, o);
    await access(c, o, b.token);
  }
  if (Date.parse(o.expires_at) <= Date.now())
    fail(410, "expired", "This offer has expired.");
  if (!["open", "proposed"].includes(o.state))
    fail(409, "conflict", "This offer has already ended.");
  const stmts: Statement[] = [
    guard(
      c.env,
      "EXISTS(SELECT 1 FROM offers WHERE id=? AND state=? AND julianday(expires_at)>julianday('now'))",
      id,
      o.state,
    ),
  ];
  let result: string;
  if (action === "accept") {
    if (o.kind !== "gift" || o.state !== "open")
      fail(409, "conflict", "A swap needs a proposal and sender confirmation.");
    result = "accepted";
    stmts.push(
      sql(
        c.env,
        "UPDATE offers SET recipient_id=?,state='accepted' WHERE id=?",
        c.account.id,
        id,
      ),
    );
  } else if (action === "propose") {
    if (o.kind !== "swap" || o.state !== "open")
      fail(409, "conflict", "This offer is not awaiting a swap proposal.");
    const cardID = str(b.cardID, 100)!,
      version = num(b.cardVersion, 1, 2147483647, true);
    if (cardID === o.card_id)
      fail(400, "invalid_request", "Offer a different owned card.");
    stmts.push(
      guard(
        c.env,
        "EXISTS(SELECT 1 FROM cards WHERE id=? AND owner_id=? AND version=?)",
        cardID,
        c.account.id,
        version,
      ),
      guard(
        c.env,
        "EXISTS(SELECT 1 FROM cards WHERE id=? AND owner_id=? AND version=?)",
        o.card_id,
        o.sender_id,
        o.card_version,
      ),
      guard(
        c.env,
        "NOT EXISTS(SELECT 1 FROM blocks WHERE (account_id=? AND blocked_id=?) OR (account_id=? AND blocked_id=?))",
        c.account.id,
        o.sender_id,
        o.sender_id,
        c.account.id,
      ),
      sql(
        c.env,
        "UPDATE offers SET recipient_id=?,proposed_card_id=?,proposed_card_version=?,state='proposed' WHERE id=?",
        c.account.id,
        cardID,
        version,
        id,
      ),
    );
    result = "proposed";
  } else if (action === "confirm") {
    if (o.kind !== "swap" || o.state !== "proposed")
      fail(409, "conflict", "This swap has no proposal to confirm.");
    await interaction(c, o);
    stmts.push(sql(c.env, "UPDATE offers SET state='accepted' WHERE id=?", id));
    result = "accepted";
  } else if (action === "cancel") {
    stmts.push(
      sql(c.env, "UPDATE offers SET state='cancelled' WHERE id=?", id),
    );
    result = "cancelled";
  } else if (action === "decline") {
    stmts.push(
      sql(
        c.env,
        "UPDATE offers SET recipient_id=COALESCE(recipient_id,?),state='declined' WHERE id=?",
        c.account.id,
        id,
      ),
    );
    result = "declined";
  } else fail(404, "not_found", "This action could not be found.");
  const recipient =
    o.recipient_id ?? (c.account.id !== o.sender_id ? c.account.id : null);
  const other = o.sender_id === c.account.id ? recipient : o.sender_id;
  if (other)
    stmts.push(
      event(c, other, "offer" + result[0].toUpperCase() + result.slice(1), id),
    );
  return command(c, { ok: true, offerID: id }, stmts);
}
export async function expireOffers(env: Env): Promise<void> {
  const condition =
    "state IN ('open','proposed') AND julianday(expires_at)<=julianday('now')";
  await env.DB.batch([
    sql(
      env,
      `INSERT INTO inbox(id,account_id,type,resource_id,created_at) SELECT lower(hex(randomblob(16))),sender_id,'offerExpired',id,? FROM offers WHERE ${condition}`,
      now(),
    ),
    sql(
      env,
      `INSERT INTO inbox(id,account_id,type,resource_id,created_at) SELECT lower(hex(randomblob(16))),recipient_id,'offerExpired',id,? FROM offers WHERE ${condition} AND recipient_id IS NOT NULL`,
      now(),
    ),
    sql(env, `UPDATE offers SET state='expired' WHERE ${condition}`),
  ]);
}
