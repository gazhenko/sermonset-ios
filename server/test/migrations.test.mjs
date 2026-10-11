import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { DatabaseSync } from "node:sqlite";
import { unstable_splitSqlQuery as splitSqlQuery } from "wrangler";

const migrations = await Promise.all(
  (await readdir("migrations"))
    .filter((name) => name.endsWith(".sql"))
    .sort()
    .map(async (name) => ({
      name,
      sql: await readFile("migrations/" + name, "utf8"),
    })),
);

test("every migration reserves END; lines for the trigger's own closing line", async (t) => {
  for (const { name, sql } of migrations) {
    await t.test(name, () => {
      const triggers = splitSqlQuery(sql).filter((statement) =>
        /^\s*CREATE\s+TRIGGER\b/im.test(statement),
      );
      assert.equal(
        triggers.length,
        [...sql.matchAll(/^\s*CREATE\s+TRIGGER\b/gim)].length,
        "The splitter must retain every trigger definition",
      );
      for (const trigger of triggers) {
        // Wrangler strips only the final statement delimiter. Its splitter
        // understands quotes/comments and keeps the whole trigger together.
        const body = trigger.slice(trigger.search(/\bBEGIN\b/i) + 5).trim();
        const lines = body.split(/\r?\n/);
        assert.match(lines.pop().trim(), /^END$/i, trigger);
        assert.doesNotMatch(
          lines.join("\n"),
          /\bEND;[ \t]*$/im,
          `${name}: an inner END; line breaks production D1 migration splitting`,
        );
      }
    });
  }
});

test("Wrangler-split migrations apply individually to a fresh SQLite database", (t) => {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  for (const { name, sql } of migrations) {
    for (const statement of splitSqlQuery(sql)) {
      assert.doesNotThrow(() => db.exec(statement), `${name}: ${statement}`);
    }
  }
  assert.deepEqual(
    db
      .prepare(
        "SELECT name FROM sqlite_schema WHERE type='trigger' ORDER BY name",
      )
      .all()
      .map((row) => row.name),
    [
      "card_minted",
      "card_transferred",
      "offer_transfer",
      "ownership_mint",
      "ownership_transfer",
    ],
  );
});
