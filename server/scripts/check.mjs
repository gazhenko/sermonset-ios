import { build } from "esbuild";
import { mkdir, readFile } from "node:fs/promises";
await mkdir(".tmp", { recursive: true });
await build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  outfile: ".tmp/worker.mjs",
});
const config = await readFile("wrangler.toml", "utf8");
if (!config.includes("enabled = false"))
  throw Error("Observability must remain disabled");
console.log("Worker TypeScript bundle compiled; observability disabled.");
