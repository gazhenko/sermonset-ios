// Structural Workers bindings keep the runtime free of vendor SDK dependencies.
export interface Statement {
  bind(...values: unknown[]): Statement;
  first<T = Row>(column?: string): Promise<T | null>;
  all<T = Row>(): Promise<{ results: T[] }>;
  run(): Promise<{ meta: { changes: number } }>;
}
export interface Database {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<unknown[]>;
}
export interface StoredObject {
  body: ReadableStream<Uint8Array>;
  size: number;
  etag: string;
  arrayBuffer(): Promise<ArrayBuffer>;
  range?: { offset?: number; length?: number; suffix?: number };
}
export interface Bucket {
  get(
    key: string,
    options?: { range?: { offset: number; length?: number } },
  ): Promise<StoredObject | null>;
  head(key: string): Promise<StoredObject | null>;
  put(
    key: string,
    value: ArrayBuffer | Uint8Array | ReadableStream,
    options?: unknown,
  ): Promise<unknown>;
  delete(key: string): Promise<void>;
}
export interface Env {
  DB: Database;
  AUDIO: Bucket;
  IMAGES: Bucket;
  ASSETS?: { fetch(request: Request): Promise<Response> };
  BRAND_NAME: string;
  BRAND_SCHEME: string;
  PUBLIC_BASE_URL: string;
  TOKEN_KEY_ID: string;
  TOKEN_SIGNING_JWK?: string;
  TOKEN_PUBLIC_KEYS?: string;
  CAPABILITY_SECRET?: string;
  ADMIN_BOOTSTRAP_SECRET?: string;
}
// Rows are narrowed at the API projection boundary; private schema fields are never spread into responses.
export type Row = Record<string, any>;
export interface Context {
  request: Request;
  url: URL;
  env: Env;
  bytes: Uint8Array;
  body: Row;
  account: Row;
  session?: Row;
  key: string;
  hash: string;
}
declare global {
  class FixedLengthStream extends TransformStream<Uint8Array, Uint8Array> {
    constructor(length: number);
  }
}
