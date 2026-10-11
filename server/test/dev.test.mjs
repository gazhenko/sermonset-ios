import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  symlink,
  writeFile,
} from "node:fs/promises";
import { createServer } from "node:net";
import { request } from "node:http";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { apiClient } from "../scripts/client.mjs";

// Node's fetch ignores a custom Host header. Use HTTP directly so the
// request origin is 8787 while the connection stays on the isolated port.
function consoleFetch(url, options) {
  return new Promise((resolve, reject) => {
    const req = request(url, options, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("error", reject);
      response.on("end", () => {
        const headers = new Headers();
        for (let i = 0; i < response.rawHeaders.length; i += 2)
          headers.append(response.rawHeaders[i], response.rawHeaders[i + 1]);
        resolve(
          new Response(Buffer.concat(chunks), {
            status: response.statusCode,
            headers,
          }),
        );
      });
    });
    req.on("error", reject);
    req.setTimeout(5000, () =>
      req.destroy(new Error("Console request timed out")),
    );
    req.end(options.body);
  });
}

function wrapper(cwd, args) {
  const child = spawn(process.execPath, ["scripts/dev.mjs", ...args], {
    cwd,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  for (const stream of [child.stdout, child.stderr])
    stream.on("data", (chunk) => (output += chunk));
  const closed = new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("close", (code) => resolve(code));
  });
  let ended = false;
  closed.then(() => (ended = true));
  return {
    closed,
    output: () => output,
    ended: () => ended,
    async stop() {
      if (ended) return;
      // Only signal the process group created by this test's detached spawn.
      process.kill(-child.pid, "SIGTERM");
      await Promise.race([closed, delay(5000, undefined, { ref: false })]);
      if (!ended) process.kill(-child.pid, "SIGKILL");
      await closed;
    },
  };
}

test(
  "dev wrapper preserves the local console Origin through Wrangler sign-in",
  { timeout: 60000 },
  async (t) => {
    const port = 8795;
    const probe = createServer();
    await new Promise((resolve, reject) => {
      probe.once("error", reject);
      probe.listen(port, "127.0.0.1", resolve);
    });
    await new Promise((resolve) => probe.close(resolve));

    // Copy the wrapper/config into an ignored workspace so the active dev
    // server's config, registry, secrets, and persistence are never changed.
    const source = resolve(".");
    const persistenceRoot = resolve("../build/wrangler-codex");
    await mkdir(persistenceRoot, { recursive: true });
    const fixture = await mkdtemp(resolve(persistenceRoot, "dev-wrapper-"));
    const cwd = resolve(fixture, "server");
    await mkdir(resolve(cwd, "scripts"), { recursive: true });
    await mkdir(resolve(fixture, "web"));
    await writeFile(
      resolve(fixture, "web/index.html"),
      "<!doctype html><p>Console fixture</p>",
    );
    const production = await readFile("wrangler.toml", "utf8");
    await writeFile(resolve(cwd, "wrangler.toml"), production);
    await cp("scripts/dev.mjs", resolve(cwd, "scripts/dev.mjs"));
    await cp("src", resolve(cwd, "src"), { recursive: true });
    await cp("migrations", resolve(cwd, "migrations"), { recursive: true });
    await symlink(
      resolve(source, "node_modules"),
      resolve(cwd, "node_modules"),
    );

    const persist = ["--persist-to", "../build/wrangler-codex"];
    const migrate = wrapper(cwd, [
      "d1",
      "migrations",
      "apply",
      "DB",
      "--local",
      ...persist,
    ]);
    t.after(() => migrate.stop());
    assert.equal(await migrate.closed, 0, migrate.output());
    const dev = wrapper(cwd, [
      "dev",
      "--local",
      "--ip",
      "127.0.0.1",
      "--port",
      String(port),
      "--inspector-port",
      "0",
      ...persist,
    ]);
    t.after(() => dev.stop());
    const transport = `http://127.0.0.1:${port}`;
    const deadline = Date.now() + 30000;
    let ready = false;
    while (Date.now() < deadline && !dev.ended()) {
      try {
        const response = await fetch(transport + "/health", {
          signal: AbortSignal.timeout(1000),
        });
        ready = response.ok;
        await response.text();
        if (ready) break;
      } catch {}
      await delay(100);
    }
    assert(ready, "Isolated Wrangler did not become ready:\n" + dev.output());

    const client = apiClient(fetch, transport);
    const who = await client.account("Dev console fixture");
    const link = await client.call(who, "POST", "/v1/web/link-codes", {});
    const options = {
      method: "POST",
      headers: {
        "content-type": "application/json",
        // Keep the HTTP Host and Origin the same as the configured console;
        // the socket connects to 8795, leaving the other session's 8787 alone.
        host: "127.0.0.1:8787",
        origin: "http://127.0.0.1:8787",
      },
      body: JSON.stringify({ code: link.code }),
    };
    const response = await consoleFetch(transport + "/v1/web/session", options);
    const body = await response.json();
    assert.equal(response.status, 200, JSON.stringify(body));
    assert.equal(body.account.id, who.id);
    assert(body.csrfToken);
    const cookie = response.headers.get("set-cookie");
    assert(cookie.includes("HttpOnly"));
    assert(cookie.includes("SameSite=Strict"));
    const me = await fetch(transport + "/v1/me", {
      headers: { cookie: cookie.split(";")[0] },
    });
    assert.equal(me.status, 200);
    assert.equal((await me.json()).account.id, who.id);
    assert.equal(
      (await consoleFetch(transport + "/v1/web/session", options)).status,
      401,
    );

    const otherLink = await client.call(who, "POST", "/v1/web/link-codes", {});
    const foreign = await consoleFetch(transport + "/v1/web/session", {
      ...options,
      headers: { ...options.headers, origin: "https://attacker.invalid" },
      body: JSON.stringify({ code: otherLink.code }),
    });
    assert.equal(foreign.status, 403);
    await foreign.text();

    const config = await readFile(
      resolve(cwd, ".tmp/wrangler.local.toml"),
      "utf8",
    );
    assert.doesNotMatch(config, /^\s*(routes|workers_dev)\s*=/m);
    assert.doesNotMatch(config, /custom_domain/);
    assert.match(config, /PUBLIC_BASE_URL = "http:\/\/127\.0\.0\.1:8787"/);
    assert.match(config, /BRAND_NAME = "SOWER"/);
    assert.match(config, /BRAND_SCHEME = "sower"/);
    assert.match(config, /\[assets\]/);
    assert.match(config, /enabled = false/);
    assert.equal(
      await readFile(resolve(cwd, "wrangler.toml"), "utf8"),
      production,
    );
    assert.equal(
      await readFile(resolve(source, "wrangler.toml"), "utf8"),
      production,
    );
  },
);
