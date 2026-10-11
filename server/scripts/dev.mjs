import { readFile, writeFile, access, mkdir, chmod } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("..", import.meta.url));
process.chdir(root);
await mkdir(".tmp", { recursive: true, mode: 0o700 });
let config = await readFile("wrangler.toml", "utf8");
// Production routes make Wrangler rewrite same-origin request headers.
// Keep local routing and the console origin independent of the public domain.
config = config
  .replace(
    /^[ \t]*routes[ \t]*=[ \t]*\[[\s\S]*?\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|$)/gm,
    "",
  )
  .replace(/^[ \t]*workers_dev[ \t]*=[^\r\n]*(?:\r?\n|$)/gm, "")
  .replace(
    /PUBLIC_BASE_URL = "[^"]+"/,
    'PUBLIC_BASE_URL = "http://127.0.0.1:8787"',
  );
try {
  await access("../web");
} catch {
  config = config.replace(/\[assets\][\s\S]*?(?=\n\[|$)/, "");
  console.log(
    "Static web directory is absent; API and server fallback pages remain available.",
  );
}
config = config
  .replace('main = "src/index.ts"', `main = "${resolve("src/index.ts")}"`)
  .replace(
    'migrations_dir = "migrations"',
    `migrations_dir = "${resolve("migrations")}"`,
  )
  .replace('directory = "../web"', `directory = "${resolve("../web")}"`);
async function writeIfChanged(path, value) {
  let existing;
  try {
    existing = await readFile(path, "utf8");
  } catch {}
  if (existing !== value) await writeFile(path, value, { mode: 0o600 });
  await chmod(path, 0o600);
}
await writeIfChanged(".tmp/wrangler.local.toml", config);
try {
  await writeIfChanged(".tmp/.dev.vars", await readFile(".dev.vars", "utf8"));
} catch {
  console.log(
    "Run node scripts/local-keys.mjs for local-only signing secrets.",
  );
}
const args = process.argv.slice(2);
if (args.includes("--remote") || !["dev", "d1", "r2"].includes(args[0]))
  throw new Error("This wrapper only permits local dev/D1/R2 commands.");
const child = spawn(
  resolve("node_modules/.bin/wrangler"),
  [...args, "--config", ".tmp/wrangler.local.toml"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      WRANGLER_SEND_METRICS: "false",
      WRANGLER_HIDE_BANNER: "true",
      WRANGLER_LOG_PATH: resolve(".tmp/wrangler-logs"),
      WRANGLER_REGISTRY_PATH: resolve(".tmp/wrangler-registry"),
      X_LOCAL_OBSERVABILITY: "false",
      X_LOCAL_EXPLORER: "false",
    },
  },
);
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => child.kill(signal));
child.on("exit", (code) => process.exit(code ?? 1));
