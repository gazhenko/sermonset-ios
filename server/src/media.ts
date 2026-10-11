import type { Bucket, Env, Row } from "./types";
import { checkCapability } from "./security";
import { fail, json, one, sql } from "./common";

// Incremental SHA-256 avoids buffering a 200 MB recording in the Worker heap.
const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);
const rr = (n: number, b: number) => (n >>> b) | (n << (32 - b));
export class StreamingSHA256 {
  private h = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
    0x1f83d9ab, 0x5be0cd19,
  ]);
  private buffer = new Uint8Array(64);
  private used = 0;
  private length = 0;
  private w = new Uint32Array(64);
  update(bytes: Uint8Array) {
    this.length += bytes.length;
    let offset = 0;
    while (offset < bytes.length) {
      const n = Math.min(64 - this.used, bytes.length - offset);
      this.buffer.set(bytes.subarray(offset, offset + n), this.used);
      offset += n;
      this.used += n;
      if (this.used === 64) {
        this.block(this.buffer);
        this.used = 0;
      }
    }
  }
  private block(data: Uint8Array) {
    const w = this.w;
    const view = new DataView(data.buffer, data.byteOffset, 64);
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(i * 4);
    for (let i = 16; i < 64; i++) {
      const x = w[i - 15],
        y = w[i - 2];
      w[i] =
        w[i - 16] +
        (rr(x, 7) ^ rr(x, 18) ^ (x >>> 3)) +
        w[i - 7] +
        (rr(y, 17) ^ rr(y, 19) ^ (y >>> 10));
    }
    let [a, b, c, d, e, f, g, h] = this.h;
    for (let i = 0; i < 64; i++) {
      const t1 =
        (h +
          (rr(e, 6) ^ rr(e, 11) ^ rr(e, 25)) +
          ((e & f) ^ (~e & g)) +
          K[i] +
          w[i]) >>>
        0;
      const t2 =
        ((rr(a, 2) ^ rr(a, 13) ^ rr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>>
        0;
      h = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    for (const [i, v] of [a, b, c, d, e, f, g, h].entries())
      this.h[i] = (this.h[i] + v) >>> 0;
  }
  digest() {
    const bits = this.length * 8;
    this.buffer[this.used++] = 0x80;
    if (this.used > 56) {
      this.buffer.fill(0, this.used);
      this.block(this.buffer);
      this.used = 0;
    }
    this.buffer.fill(0, this.used, 56);
    const view = new DataView(this.buffer.buffer);
    view.setUint32(56, Math.floor(bits / 4294967296));
    view.setUint32(60, bits >>> 0);
    this.block(this.buffer);
    return [...this.h].map((n) => n.toString(16).padStart(8, "0")).join("");
  }
}
const text = (b: Uint8Array, o: number, n: number) =>
  String.fromCharCode(...b.subarray(o, o + n));
function boxes(
  b: Uint8Array,
  start = 0,
  end = b.length,
): { type: string; data: Uint8Array }[] {
  const result = [];
  let o = start;
  while (o < end) {
    if (o + 8 > end) fail(422, "invalid_audio", "Incomplete media container.");
    const v = new DataView(b.buffer, b.byteOffset + o, end - o);
    let size = v.getUint32(0),
      header = 8;
    if (size === 1) {
      if (o + 16 > end)
        fail(422, "invalid_audio", "Incomplete media container.");
      size = Number(v.getBigUint64(8));
      header = 16;
    }
    if (size < header || size > end - o)
      fail(422, "invalid_audio", "Invalid media container.");
    result.push({
      type: text(b, o + 4, 4),
      data: b.subarray(o + header, o + size),
    });
    o += size;
  }
  return result;
}
function descriptor(
  data: Uint8Array,
  offset: number,
): { tag: number; payload: Uint8Array } {
  const tag = data[offset++];
  let length = 0,
    count = 0,
    byte: number;
  do {
    if (offset >= data.length || count++ === 4)
      fail(422, "invalid_audio", "Invalid AAC descriptor.");
    byte = data[offset++];
    length = length * 128 + (byte & 127);
  } while (byte & 128);
  if (offset + length > data.length)
    fail(422, "invalid_audio", "Incomplete AAC descriptor.");
  return { tag, payload: data.subarray(offset, offset + length) };
}
function isAAC(data: Uint8Array): boolean {
  if (data.length < 4) return false;
  const es = descriptor(data, 4);
  if (es.tag !== 3 || es.payload.length < 3) return false;
  const flags = es.payload[2];
  let offset = 3;
  if (flags & 128) offset += 2;
  if (flags & 64) offset += 1 + (es.payload[offset] ?? 0);
  if (flags & 32) offset += 2;
  const decoder = descriptor(es.payload, offset);
  if (
    decoder.tag !== 4 ||
    decoder.payload.length < 13 ||
    decoder.payload[0] !== 0x40 ||
    decoder.payload[1] >>> 2 !== 5
  )
    return false;
  const config = descriptor(decoder.payload, 13);
  return (
    config.tag === 5 &&
    config.payload.length >= 2 &&
    [2, 5, 29].includes(config.payload[0] >>> 3)
  );
}
function duration(moov: Uint8Array): number {
  const tracks = boxes(moov).filter((b) => b.type === "trak");
  const durations: number[] = [];
  for (const track of tracks) {
    const mdia = boxes(track.data).find((b) => b.type === "mdia");
    if (!mdia) continue;
    const children = boxes(mdia.data);
    const hdlr = children.find((b) => b.type === "hdlr");
    if (!hdlr || hdlr.data.length < 12 || text(hdlr.data, 8, 4) !== "soun")
      fail(422, "invalid_audio", "Only AAC audio tracks are accepted.");
    const mdhd = children.find((b) => b.type === "mdhd");
    const minf = children.find((b) => b.type === "minf");
    if (!mdhd || !minf) fail(422, "invalid_audio", "Missing audio metadata.");
    const stbl = boxes(minf.data).find((b) => b.type === "stbl");
    const stsd = stbl && boxes(stbl.data).find((b) => b.type === "stsd");
    if (!stsd || stsd.data.length < 8)
      fail(422, "invalid_audio", "Missing AAC format.");
    const descriptions = boxes(stsd.data, 8);
    if (
      !descriptions.length ||
      descriptions.some((d) => d.type !== "mp4a" || d.data.length < 28)
    )
      fail(422, "invalid_audio", "An AAC M4A file is required.");
    for (const d of descriptions) {
      const esds = boxes(d.data, 28).find((b) => b.type === "esds");
      if (!esds || !isAAC(esds.data))
        fail(422, "invalid_audio", "An MPEG-4 AAC descriptor is required.");
    }
    const v = new DataView(
      mdhd.data.buffer,
      mdhd.data.byteOffset,
      mdhd.data.length,
    );
    if (mdhd.data.length < (mdhd.data[0] === 1 ? 32 : 20))
      fail(422, "invalid_audio", "Missing audio duration.");
    const timescale = v.getUint32(mdhd.data[0] === 1 ? 20 : 12);
    const ticks =
      mdhd.data[0] === 1 ? Number(v.getBigUint64(24)) : v.getUint32(16);
    if (!timescale || !ticks)
      fail(422, "invalid_audio", "Invalid audio duration.");
    durations.push(ticks / timescale);
  }
  if (durations.length !== 1)
    fail(422, "invalid_audio", "One AAC audio track is required.");
  return durations[0];
}
class ContainerCheck {
  private header = new Uint8Array(16);
  private headerUsed = 0;
  private headerNeeded = 8;
  private left = 0;
  private capture: Uint8Array | null = null;
  private captureUsed = 0;
  private type = "";
  private moov: Uint8Array | null = null;
  private ftyp = false;
  private mdat = false;
  update(chunk: Uint8Array) {
    let o = 0;
    while (o < chunk.length) {
      if (this.left > 0) {
        const n = Math.min(this.left, chunk.length - o);
        if (this.capture) {
          this.capture.set(chunk.subarray(o, o + n), this.captureUsed);
          this.captureUsed += n;
        }
        o += n;
        this.left -= n;
        if (!this.left) {
          if (this.type === "moov") this.moov = this.capture;
          if (this.type === "ftyp") {
            const data = this.capture!;
            if (
              data.length < 8 ||
              !["M4A ", "isom", "mp42", "mp41"].includes(text(data, 0, 4))
            )
              fail(422, "invalid_audio", "An M4A container is required.");
            this.ftyp = true;
          }
          this.capture = null;
        }
        continue;
      }
      const n = Math.min(this.headerNeeded - this.headerUsed, chunk.length - o);
      this.header.set(chunk.subarray(o, o + n), this.headerUsed);
      this.headerUsed += n;
      o += n;
      if (this.headerUsed < this.headerNeeded) continue;
      const v = new DataView(this.header.buffer);
      let size = v.getUint32(0);
      if (size === 1 && this.headerNeeded === 8) {
        this.headerNeeded = 16;
        continue;
      }
      if (size === 1) size = Number(v.getBigUint64(8));
      if (size < this.headerNeeded || size > 200000000)
        fail(422, "invalid_audio", "Invalid container size.");
      this.type = text(this.header, 4, 4);
      this.left = size - this.headerNeeded;
      if (this.type === "mdat") this.mdat = true;
      if (["moov", "ftyp"].includes(this.type)) {
        if (
          this.left > 8 * 1024 * 1024 ||
          (this.type === "ftyp" && this.left > 4096)
        )
          fail(422, "invalid_audio", "Media metadata exceeds the limit.");
        this.capture = new Uint8Array(this.left);
        this.captureUsed = 0;
      }
      this.headerUsed = 0;
      this.headerNeeded = 8;
    }
  }
  finish(claim: number, bytes: number) {
    if (this.left || this.headerUsed || !this.ftyp || !this.mdat || !this.moov)
      fail(422, "invalid_audio", "Incomplete M4A audio.");
    const measured = duration(this.moov);
    if (
      measured > 10800 ||
      Math.abs(measured - claim) > Math.max(1, claim * 0.01) ||
      bytes / measured < 500 ||
      bytes / measured > 100000
    )
      fail(
        422,
        "invalid_audio",
        "Audio duration or size does not match the upload.",
      );
  }
}
async function upload(
  request: Request,
  bucket: Bucket,
  key: string,
  expected: Row,
  audio: boolean,
): Promise<void> {
  if (!request.body) fail(400, "invalid_request", "Upload bytes are required.");
  const length = request.headers.get("content-length");
  if (length && Number(length) !== expected.byte_count)
    fail(
      422,
      audio ? "invalid_audio" : "invalid_request",
      "Upload size does not match.",
    );
  const temp = `private/staging/${crypto.randomUUID()}`;
  const hash = new StreamingSHA256();
  const container = audio ? new ContainerCheck() : null;
  let count = 0;
  const png = new Uint8Array(8);
  let pngUsed = 0;
  let validationError: unknown;
  const stream = request.body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        try {
          count += chunk.length;
          if (count > expected.byte_count)
            fail(413, "too_large", "Upload exceeds its authorized size.");
          hash.update(chunk);
          container?.update(chunk);
          if (!audio && pngUsed < 8) {
            const n = Math.min(8 - pngUsed, chunk.length);
            png.set(chunk.subarray(0, n), pngUsed);
            pngUsed += n;
          }
          controller.enqueue(chunk);
        } catch (error) {
          validationError = error;
          throw error;
        }
      },
    }),
  );
  try {
    try {
      await bucket.put(
        temp,
        stream.pipeThrough(new FixedLengthStream(expected.byte_count)),
      );
    } catch (error) {
      if (validationError) throw validationError;
      if (count !== expected.byte_count)
        fail(
          422,
          audio ? "invalid_audio" : "invalid_request",
          "Upload size does not match.",
        );
      throw error;
    }
    if (count !== expected.byte_count || hash.digest() !== expected.checksum)
      fail(
        422,
        audio ? "invalid_audio" : "invalid_request",
        "Upload checksum or size does not match.",
      );
    if (audio) container!.finish(expected.duration, count);
    else if (
      pngUsed !== 8 ||
      [137, 80, 78, 71, 13, 10, 26, 10].some((v, i) => png[i] !== v)
    )
      fail(422, "invalid_request", "A PNG image is required.");
    const staged = await bucket.get(temp);
    if (!staged) fail(500, "internal_error", "Upload could not be stored.");
    await bucket.put(key, staged.body, {
      httpMetadata: { contentType: audio ? "audio/mp4" : "image/png" },
    });
  } finally {
    await bucket.delete(temp);
  }
}
export async function audioUpload(
  request: Request,
  env: Env,
  id: string,
  url: URL,
): Promise<Response> {
  await checkCapability(env, "upload", id, url.searchParams.get("token"));
  const asset = await one(env, "SELECT * FROM audio_assets WHERE id=?", id);
  if (
    asset.uploaded &&
    asset.owner_id &&
    asset.upload_expires >= Date.now() / 1000
  )
    return json({ ok: true });
  if (
    !["pendingUpload", "uploading", "quarantine"].includes(asset.state) ||
    asset.upload_expires < Date.now() / 1000
  )
    fail(409, "conflict", "This publication is no longer accepting uploads.");
  if (request.headers.get("content-type")?.split(";")[0] !== "audio/mp4")
    fail(422, "invalid_audio", "Use audio/mp4.");
  if (asset.uploaded) return json({ ok: true });
  await env.DB.batch([
    sql(
      env,
      "UPDATE audio_assets SET state='uploading' WHERE id=? AND state='pendingUpload'",
      id,
    ),
    sql(
      env,
      "UPDATE publications SET state='uploading' WHERE id=? AND state='pendingUpload'",
      asset.publication_id,
    ),
  ]);
  await upload(request, env.AUDIO, asset.storage_key, asset, true);
  const result = await env.DB.batch([
    sql(
      env,
      "UPDATE audio_assets SET uploaded=1,validated=1,state='quarantine' WHERE id=? AND owner_id IS NOT NULL AND state IN ('pendingUpload','uploading','quarantine')",
      id,
    ),
    sql(
      env,
      "UPDATE publications SET state='quarantine' WHERE id=? AND state IN ('pendingUpload','uploading','quarantine')",
      asset.publication_id,
    ),
  ]);
  if (!(result[0] as { meta: { changes: number } }).meta.changes) {
    const current = await sql(
      env,
      "SELECT owner_id,uploaded FROM audio_assets WHERE id=?",
      id,
    ).first();
    if (current?.owner_id && current.uploaded) return json({ ok: true });
    await env.AUDIO.delete(asset.storage_key);
    fail(409, "conflict", "This publication changed while uploading.");
  }
  return json({ ok: true });
}
export async function imageUpload(
  request: Request,
  env: Env,
  id: string,
  url: URL,
): Promise<Response> {
  await checkCapability(env, "image", id, url.searchParams.get("token"));
  const share = await one(env, "SELECT * FROM shares WHERE id=?", id);
  if (share.upload_expires < Date.now() / 1000)
    fail(410, "expired", "This upload expired.");
  if (request.headers.get("content-type")?.split(";")[0] !== "image/png")
    fail(422, "invalid_request", "Use image/png.");
  if (!share.uploaded) {
    await upload(request, env.IMAGES, share.storage_key, share, false);
    const updated = await sql(
      env,
      "UPDATE shares SET uploaded=1 WHERE id=? AND account_id IS NOT NULL",
      id,
    ).run();
    if (!updated.meta.changes) {
      await env.IMAGES.delete(share.storage_key);
      fail(409, "conflict", "This share was removed while uploading.");
    }
  }
  return json({ ok: true });
}
