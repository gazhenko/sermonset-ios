// Test-only entrypoint. Production wrangler.toml always uses src/index.ts.
import worker, { scheduled } from "../src/index";
import { StreamingSHA256 } from "../src/media";
export default {
  async fetch(request: Request, env: any): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/__fixture/cron") {
      await scheduled(
        env,
        new URL(request.url).searchParams.get("cron") ?? "0 * * * *",
      );
      return Response.json({ ok: true });
    }
    if (path === "/__fixture/hash") {
      const hash = new StreamingSHA256();
      const reader = request.body!.getReader();
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        hash.update(value);
      }
      return Response.json({ hash: hash.digest() });
    }
    return worker.fetch(request, env);
  },
};
