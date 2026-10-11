// Browser client for the Sower community API (docs/api/API.md, API-VERSION 1).
// Same-origin only: the session is an HttpOnly cookie; writes carry the CSRF token and an
// Idempotency-Key, so a retried click never applies twice.

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message || "Something went wrong. Try again.");
    this.status = status;
    this.code = code || "internal_error";
  }
}

export class Api {
  constructor() {
    this.csrf = null;
    this.account = null;
  }

  async #request(method, path, { body, params, idempotent = true } = {}) {
    const url = new URL(path, location.origin);
    if (params) {
      for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== null && value !== "") url.searchParams.set(key, value);
      }
    }
    const headers = { Accept: "application/json" };
    const init = { method, headers, credentials: "same-origin" };
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    if (method !== "GET" && method !== "HEAD") {
      if (this.csrf) headers["X-CSRF-Token"] = this.csrf;
      if (idempotent) headers["Idempotency-Key"] = crypto.randomUUID();
    }
    let response;
    try {
      response = await fetch(url, init);
    } catch {
      throw new ApiError(0, "offline", "Can’t reach SOWER. Check your connection and try again.");
    }
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = null; }
    if (!response.ok) {
      const err = data?.error ?? {};
      throw new ApiError(response.status, err.code, err.message);
    }
    return data;
  }

  get(path, params) { return this.#request("GET", path, { params }); }
  post(path, body = {}) { return this.#request("POST", path, { body }); }
  patch(path, body = {}) { return this.#request("PATCH", path, { body }); }
  delete(path) { return this.#request("DELETE", path, { body: {} }); }

  /** Fetches every page of a list endpoint (bounded, for console tables). */
  async all(path, params = {}, max = 500) {
    const items = [];
    let cursor = null;
    do {
      const page = await this.get(path, { ...params, limit: 100, cursor });
      items.push(...(page?.items ?? []));
      cursor = page?.nextCursor ?? null;
    } while (cursor && items.length < max);
    return items;
  }

  async restore() {
    try {
      const session = await this.get("/v1/web/session");
      this.csrf = session.csrfToken;
      this.account = session.account;
      return session.account;
    } catch (error) {
      if (error.status === 401) return null;
      throw error;
    }
  }

  async signInWithCode(code) {
    const session = await this.#request("POST", "/v1/web/session", { body: { code: code.trim() }, idempotent: false });
    this.csrf = session.csrfToken;
    this.account = session.account;
    return session.account;
  }

  async signInWithBootstrap(bootstrapSecret, accountID) {
    const session = await this.#request("POST", "/v1/web/session", {
      body: { bootstrapSecret, accountID: accountID.trim() }, idempotent: false,
    });
    this.csrf = session.csrfToken;
    this.account = session.account;
    return session.account;
  }

  async signOut() {
    try { await this.#request("DELETE", "/v1/web/session", { idempotent: false }); } catch { /* already gone */ }
    this.csrf = null;
    this.account = null;
  }

  hasRole(...roles) {
    return (this.account?.roles ?? []).some((r) => roles.includes(r.role));
  }
}

// ---- Small DOM helpers shared by the consoles ----

/** Creates an element: h("button", {class: "btn", onclick}, "Label"). Text is always set as text. */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props ?? {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key.startsWith("on") && typeof value === "function") el.addEventListener(key.slice(2), value);
    else if (key === "class") el.className = value;
    else if (key === "dataset") Object.assign(el.dataset, value);
    else if (value === true) el.setAttribute(key, "");
    else el.setAttribute(key, value);
  }
  for (const child of children.flat()) {
    if (child === undefined || child === null || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

export function formatDate(iso, withTime = false) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, withTime
    ? { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" }
    : { month: "short", day: "numeric", year: "numeric" });
}

export function clock(seconds) {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds)) return "—";
  const s = Math.max(0, Math.floor(seconds));
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, "0")}`;
}

/** Shows a modal asking for a required reason; resolves to the text or null if cancelled. */
export function askReason({ title, detail, confirmLabel = "Confirm", danger = false }) {
  return new Promise((resolve) => {
    const field = h("textarea", { id: "reason-input", required: true, maxlength: "500" });
    const error = h("p", { class: "faint", role: "alert" });
    const dialog = h("dialog", { "aria-labelledby": "reason-title" },
      h("form", { method: "dialog", class: "stack" },
        h("h2", { id: "reason-title", class: "display dialog-title" }, title),
        detail ? h("p", { class: "muted" }, detail) : null,
        h("label", { for: "reason-input" }, "Reason", h("span", { class: "hint" }, "Recorded in the audit log and shown to the people affected."), field),
        error,
        h("div", { class: "row" },
          h("button", { class: `btn ${danger ? "danger" : "primary"}`, value: "ok" }, confirmLabel),
          h("button", { class: "btn", value: "cancel", formnovalidate: true }, "Cancel"))));
    document.body.append(dialog);
    dialog.addEventListener("close", () => {
      const ok = dialog.returnValue === "ok" && field.value.trim();
      dialog.remove();
      resolve(ok ? field.value.trim() : null);
    });
    dialog.querySelector("form").addEventListener("submit", (event) => {
      const submitter = event.submitter;
      if (submitter?.value === "ok" && !field.value.trim()) {
        event.preventDefault();
        error.textContent = "Add a short reason first.";
        field.focus();
      }
    });
    dialog.showModal();
    field.focus();
  });
}

/** Announces a status message in a live region at the top of the page. */
export function announce(message, kind = "info") {
  const region = document.getElementById("status");
  if (!region) return;
  region.replaceChildren(h("div", { class: `notice ${kind === "error" ? "error" : kind === "ok" ? "" : "info"}` }, message));
  if (kind !== "error") setTimeout(() => { if (region.textContent === message) region.replaceChildren(); }, 6000);
}

export async function sha256Hex(buffer) {
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
