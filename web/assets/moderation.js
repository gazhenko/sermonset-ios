// SOWER moderation: every queue the trust-and-safety process needs, with a reason on every action
// and a full audit log. Data here is role-restricted and never includes private listener material.
import { Api, ApiError, h, formatDate, clock, askReason, announce } from "/assets/api.js";

const api = new Api();
const view = document.getElementById("view");
const accountBox = document.getElementById("account");

const QUEUES = [
  ["reports", "Reports"], ["publications", "Shared recordings"], ["claims", "Church claims"],
  ["appeals", "Appeals"], ["removals", "Church removals"], ["audit", "Audit log"],
];
const BASIS_LABEL = { none: "Card only, no audio", churchReview: "Asked for church review", serviceQR: "Service QR code", official: "Official audio", fictionalSeed: "Sample data" };
const REASON = {
  rights: "Rights violation", privacy: "Privacy concern", wrongAttribution: "Wrong attribution",
  misleadingEdit: "Misleading edit", sensitiveContent: "Sensitive personal content", abuse: "Abuse or impersonation",
};
const STATE_LABEL = {
  pendingUpload: "Waiting for upload", uploading: "Uploading", quarantine: "Quarantined", validating: "Checking file",
  pendingRights: "Needs rights review", approved: "Approved", published: "Published", rejected: "Rejected",
  disputed: "Disputed", removed: "Removed", superseded: "Superseded", open: "Open", resolved: "Resolved",
  approve: "Approved", reject: "Rejected", pending: "Pending",
};

let queue = "reports";
const counts = {};

function errorText(error) {
  return error instanceof ApiError ? error.message : "Something went wrong. Try again.";
}

async function start() {
  try {
    const account = await api.restore();
    account ? render() : renderSignIn();
  } catch (err) {
    view.replaceChildren(h("div", { class: "notice error" }, errorText(err)));
  }
}

function renderAccount() {
  accountBox.replaceChildren();
  if (!api.account) return;
  const role = api.hasRole("admin") ? "Admin" : api.hasRole("moderator") ? "Moderator" : "No moderation role";
  accountBox.append(
    h("span", { class: "tag" }, role),
    h("span", {}, api.account.displayName || "SOWER account"),
    h("button", { class: "btn link", onclick: async () => { await api.signOut(); renderSignIn(); } }, "Sign out"));
}

function renderSignIn() {
  renderAccount();
  const code = h("input", { id: "code", class: "code-input", autocomplete: "one-time-code", required: true, maxlength: "12" });
  const error = h("p", { role: "alert", class: "faint" });
  const secret = h("input", { id: "secret", type: "password", autocomplete: "off" });
  const accountID = h("input", { id: "acct", autocomplete: "off" });
  const form = h("form", { class: "panel signin" },
    h("div", { class: "page-head" }, h("h1", { class: "display" }, "Moderation"),
      h("p", { class: "muted" }, "Sign in with a code from SOWER on your iPhone: Settings › Community › your name › Link a browser.")),
    h("label", { for: "code" }, "Code", code),
    error,
    h("div", { class: "form-actions" }, h("button", { class: "btn primary" }, "Sign in")),
    h("details", {},
      h("summary", {}, "First-time setup (admin)"),
      h("div", { class: "stack" },
        h("p", { class: "faint" }, "Makes an existing account the first admin. The setup secret is stored only as a Worker secret."),
        h("label", { for: "acct" }, "Your account ID", h("span", { class: "hint" }, "In SOWER: Settings › Community › your name › Account ID."), accountID),
        h("label", { for: "secret" }, "Setup secret", secret),
        h("button", { class: "btn", type: "button", onclick: async () => {
          error.textContent = "";
          try { await api.signInWithBootstrap(secret.value, accountID.value); secret.value = ""; render(); }
          catch (err) { error.textContent = errorText(err); }
        } }, "Make admin and sign in"))));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.textContent = "";
    try { await api.signInWithCode(code.value); render(); }
    catch (err) { error.textContent = err.status === 401 ? "That code didn’t work. Make a new one in the app." : errorText(err); }
  });
  view.replaceChildren(form);
  code.focus();
}

function render() {
  renderAccount();
  if (!api.hasRole("moderator", "admin")) {
    return view.replaceChildren(h("div", { class: "panel stack" },
      h("h1", { class: "display" }, "Not a moderator"),
      h("p", {}, "This account doesn’t have a moderation role. An admin can grant one.")));
  }
  const tabs = h("div", { class: "tabs", role: "tablist", "aria-label": "Queues" },
    QUEUES.map(([id, label]) => h("button", {
      role: "tab", id: `tab-${id}`, "aria-selected": String(queue === id), "aria-controls": "panel",
      onclick: () => { queue = id; render(); },
    }, label, counts[id] ? h("span", { class: "count" }, String(counts[id])) : null)));
  const panel = h("section", { id: "panel", role: "tabpanel", "aria-labelledby": `tab-${queue}`, class: "stack" });
  view.replaceChildren(h("div", { class: "page-head" }, h("h1", { class: "display" }, "Moderation")), tabs, panel);
  queue === "audit" ? renderAudit(panel) : renderQueue(panel, queue);
}

async function renderQueue(panel, kind) {
  panel.replaceChildren(h("p", { class: "muted" }, "Loading…"));
  let items;
  try { items = await api.all("/v1/moderation/queue", { kind }); }
  catch (err) { return panel.replaceChildren(h("div", { class: "notice error" }, errorText(err))); }
  const open = items.filter((i) => !["resolved", "rejected", "published", "removed", "approve", "reject"].includes(i.state));
  counts[kind] = open.length;
  document.querySelector(`#tab-${kind} .count`)?.remove();
  if (open.length) document.getElementById(`tab-${kind}`)?.append(h("span", { class: "count" }, String(open.length)));
  if (!items.length) {
    return panel.replaceChildren(h("div", { class: "panel quiet empty" }, h("strong", {}, "All clear"), "Nothing is waiting in this queue."));
  }
  const builders = { reports: reportItem, publications: publicationItem, claims: claimItem, appeals: appealItem, removals: removalItem };
  panel.replaceChildren(h("div", { class: "items" }, items.map(builders[kind])));
}

async function act(targetType, targetID, action, copy) {
  const reason = await askReason(copy);
  if (!reason) return;
  try {
    await api.post("/v1/moderation/actions", { targetType, targetID, action, reason });
    announce("Done. The action is in the audit log.", "ok");
    render();
  } catch (err) { announce(errorText(err), "error"); }
}

function stateTag(state) {
  const tone = ["published", "resolved", "approve"].includes(state) ? "lime ok" : ["disputed", "removed", "rejected", "reject"].includes(state) ? "coral" : "warn";
  return h("span", { class: `tag ${tone}` }, STATE_LABEL[state] ?? state);
}

function reportItem(r) {
  const contentActions = r.targetType === "sermon" || r.targetType === "audio"
    ? [
        h("button", { class: "btn", onclick: () => act("sermon", r.targetID, "dispute", { title: "Mark as disputed", detail: "Playback pauses while the concern is reviewed. Cards and history stay.", confirmLabel: "Dispute" }) }, "Pause audio (dispute)"),
        h("button", { class: "btn danger", onclick: () => act("audio", r.targetID, "remove", { title: "Remove audio", detail: "Public playback stops. The sermon, cards, and listeners’ history stay.", confirmLabel: "Remove audio", danger: true }) }, "Remove audio"),
      ]
    : r.targetType === "account" && api.hasRole("admin")
      ? [h("button", { class: "btn danger", onclick: () => act("account", r.targetID, "ban", { title: "Ban account", detail: "They can’t publish, trade, or listen through their account.", confirmLabel: "Ban", danger: true }) }, "Ban account")]
      : [];
  return h("article", { class: "panel item" },
    h("div", { class: "item-head" }, h("h3", {}, REASON[r.reason] ?? r.reason), stateTag(r.state)),
    h("div", { class: "meta" },
      h("span", {}, `${r.targetType[0].toUpperCase()}${r.targetType.slice(1)}: ${r.targetSummary ?? r.targetID}`),
      r.timestamp !== null && r.timestamp !== undefined ? h("span", {}, `At ${clock(r.timestamp)}`) : null,
      h("span", {}, `Reported ${formatDate(r.createdAt, true)}`)),
    r.details ? h("p", {}, r.details) : h("p", { class: "faint" }, "No details given."),
    r.state === "resolved" ? null : h("div", { class: "form-actions" },
      ...contentActions,
      h("button", { class: "btn", onclick: () => act("report", r.id, "resolve", { title: "Resolve report", detail: "Close the report with a note about what you did or why no action was needed.", confirmLabel: "Resolve" }) }, "Resolve")));
}

function publicationItem(p) {
  const review = p.review ?? null;
  const player = h("div");
  return h("article", { class: "panel item" },
    h("div", { class: "item-head" }, h("h3", {}, review?.title ?? "Shared recording"), stateTag(p.state)),
    h("div", { class: "meta" },
      review?.preacher ? h("span", {}, review.preacher) : null,
      review?.serviceDate ? h("span", {}, formatDate(review.serviceDate)) : null,
      review?.rightsBasis ? h("span", {}, BASIS_LABEL[review.rightsBasis] ?? review.rightsBasis) : null,
      review?.audio ? h("span", {}, `Audio ${clock(review.audio.duration)}`) : h("span", {}, "No audio"),
      h("span", {}, `Created ${formatDate(p.createdAt, true)}`)),
    review?.summary ? h("p", {}, review.summary) : null,
    player,
    h("div", { class: "form-actions" },
      p.audioAssetID ? h("button", { class: "btn", onclick: async (e) => {
        e.target.disabled = true;
        try {
          const { url } = await api.post(`/v1/moderation/publications/${p.id}/preview-url`);
          player.replaceChildren(h("audio", { controls: true, src: url, preload: "metadata", "aria-label": "Listen to the recording" }));
        } catch (err) { player.replaceChildren(h("p", { class: "faint" }, err.status === 404 ? "Listening before approval isn’t available yet." : errorText(err))); }
      } }, "Listen") : null,
      p.state === "pendingRights" ? h("button", { class: "btn primary", onclick: () => act("publication", p.id, "approve", { title: "Approve", detail: "Only approve when there is a valid rights basis (church approval, official upload, or a valid service code that allows sharing).", confirmLabel: "Approve" }) }, "Approve") : null,
      p.state === "pendingRights" ? h("button", { class: "btn danger", onclick: () => act("publication", p.id, "reject", { title: "Reject", detail: "The listener keeps their private recording.", confirmLabel: "Reject", danger: true }) }, "Reject") : null,
      p.state === "published" ? h("button", { class: "btn", onclick: () => act("publication", p.id, "dispute", { title: "Dispute", detail: "Pause playback while you review.", confirmLabel: "Dispute" }) }, "Dispute") : null,
      ["disputed", "removed"].includes(p.state) ? h("button", { class: "btn", onclick: () => act("publication", p.id, "restore", { title: "Restore", detail: "Restoring only works while a valid rights grant still exists.", confirmLabel: "Restore" }) }, "Restore") : null));
}

function claimItem(c) {
  let host = c.website;
  try { host = new URL(c.website).host; } catch { /* keep as typed */ }
  return h("article", { class: "panel item" },
    h("div", { class: "item-head" }, h("h3", {}, c.name), stateTag(c.state)),
    h("div", { class: "meta" },
      h("span", {}, c.role),
      h("span", {}, h("a", { href: c.website, target: "_blank", rel: "noopener noreferrer" }, host)),
      h("span", {}, `Claimed ${formatDate(c.createdAt, true)}`)),
    h("p", {}, c.evidence),
    ["pending", "open"].includes(c.state) ? h("div", { class: "form-actions" },
      h("button", { class: "btn primary", onclick: () => act("claim", c.id, "approve", { title: "Verify church", detail: "Grants this account church staff access and marks the church verified. Verification is identity only, not endorsement.", confirmLabel: "Verify" }) }, "Verify"),
      h("button", { class: "btn danger", onclick: () => act("claim", c.id, "reject", { title: "Decline claim", detail: "Tell them what evidence would work.", confirmLabel: "Decline", danger: true }) }, "Decline")) : null);
}

function appealItem(a) {
  return h("article", { class: "panel item" },
    h("div", { class: "item-head" }, h("h3", {}, "Appeal"), stateTag(a.state)),
    h("div", { class: "meta" }, h("span", {}, `Action ${a.actionID}`), h("span", {}, `Filed ${formatDate(a.createdAt, true)}`)),
    h("p", {}, a.reason),
    ["pending", "open"].includes(a.state) ? h("div", { class: "form-actions" },
      h("button", { class: "btn primary", onclick: () => act("appeal", a.id, "approve", { title: "Uphold appeal", detail: "Reverse the original action where the rules allow.", confirmLabel: "Uphold" }) }, "Uphold"),
      h("button", { class: "btn", onclick: () => act("appeal", a.id, "reject", { title: "Keep the decision", detail: "Explain why the original action stands.", confirmLabel: "Keep decision" }) }, "Keep decision")) : null);
}

function removalItem(r) {
  return h("article", { class: "panel item" },
    h("div", { class: "item-head" }, h("h3", {}, "Church removed audio"), h("span", { class: "tag coral" }, "Audio off")),
    h("div", { class: "meta" }, h("span", {}, `Sermon ${r.sermonID}`), h("span", {}, `Church ${r.churchID}`), h("span", {}, formatDate(r.createdAt, true))),
    h("p", {}, r.reason));
}

async function renderAudit(panel) {
  panel.replaceChildren(h("p", { class: "muted" }, "Loading…"));
  try {
    const rows = await api.all("/v1/moderation/audit", {}, 300);
    panel.replaceChildren(rows.length
      ? h("div", { class: "table-wrap" }, h("table", {},
          h("thead", {}, h("tr", {}, ["When", "Action", "Target", "Reason", "By"].map((t) => h("th", { scope: "col" }, t)))),
          h("tbody", {}, rows.map((r) => h("tr", {},
            h("td", { class: "num" }, formatDate(r.createdAt, true)),
            h("td", {}, STATE_LABEL[r.action] ?? r.action),
            h("td", {}, `${r.targetType} ${r.targetID}`),
            h("td", {}, r.reason),
            h("td", {}, r.actorID ?? "System"))))))
      : h("div", { class: "panel quiet empty" }, h("strong", {}, "No actions yet"), "Every moderation and church action will be listed here."));
  } catch (err) { panel.replaceChildren(h("div", { class: "notice error" }, errorText(err))); }
}

start();
