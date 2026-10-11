import { mkdir, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { seedData, statementSQL } from "./seed-data.mjs";
await mkdir(".tmp", { recursive: true });
const seed = await seedData();
await writeFile(
  ".tmp/seed.sql",
  seed.statements.map(statementSQL).join(";\n") + ";\n",
);
function wrangler(args) {
  const result = spawnSync(process.execPath, ["scripts/dev.mjs", ...args], {
    stdio: "inherit",
    env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
  });
  if (result.status !== 0) throw Error("Local seed command failed");
}
wrangler([
  "d1",
  "execute",
  "DB",
  "--local",
  "--persist-to",
  ".wrangler/state",
  "--file",
  ".tmp/seed.sql",
]);
for (const [i, item] of seed.audio.entries()) {
  const path = `.tmp/sample-${i}.m4a`;
  await writeFile(path, item.bytes);
  wrangler([
    "r2",
    "object",
    "put",
    `sower-audio/${item.key}`,
    "--local",
    "--persist-to",
    ".wrangler/state",
    "--file",
    path,
    "--content-type",
    "audio/mp4",
  ]);
}
console.log(
  "Seeded eight fictional sermons, eight sample audio files, and three fictional church networks. No transcripts or private sample notes were loaded.",
);
