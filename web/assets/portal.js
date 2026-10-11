// SOWER for Churches: review listener recordings, keep sermon details right, publish official
// audio, and print service QR codes. Every action goes through the API's role checks.
import { Api, ApiError, h, formatDate, clock, askReason, announce, sha256Hex } from "/assets/api.js";

const api = new Api();
const view = document.getElementById("view");
const accountBox = document.getElementById("account");

const SERMON_TYPES = ["hope", "wisdom", "grace", "courage", "conviction", "worship", "mission", "restoration"];
const STATE_LABEL = {
  pendingUpload: "Waiting for upload", uploading: "Uploading", quarantine: "Checking file", validating: "Checking file",
  pendingRights: "Needs your review", approved: "Approved", published: "Published", rejected: "Rejected",
  disputed: "Under review", removed: "Removed", superseded: "Replaced by official audio",
};
const BASIS_LABEL = { none: "Card only, no audio", churchReview: "Asked for church review", serviceQR: "Service QR code", official: "Official audio", fictionalSeed: "Sample data" };

let churches = [];
let church = null;
let tab = "review";

function errorText(error) {
  return error instanceof ApiError ? error.message : "Something went wrong. Try again.";
}

async function start() {
  try {
    const account = await api.restore();
    account ? await loadChurches() : renderSignIn();
  } catch (error) {
    view.replaceChildren(h("div", { class: "notice error" }, errorText(error)));
  }
}

// ---------- Account ----------

function renderAccount() {
  accountBox.replaceChildren();
  if (!api.account) return;
  accountBox.append(
    h("span", {}, "Signed in as ", h("strong", {}, api.account.displayName || "your SOWER account")),
    h("button", { class: "btn link", onclick: async () => { await api.signOut(); churches = []; church = null; renderSignIn(); } }, "Sign out"));
}

function renderSignIn(message) {
  renderAccount();
  const input = h("input", { id: "code", class: "code-input", autocomplete: "one-time-code", inputmode: "text", maxlength: "12", required: true, "aria-describedby": "code-help" });
  const error = h("p", { role: "alert", class: "faint" }, message ?? "");
  const form = h("form", { class: "panel signin" },
    h("div", { class: "page-head" },
      h("h1", { class: "display" }, "SOWER for churches"),
      h("p", { class: "muted" }, "Review the recordings listeners share from your services, publish your own audio, and print QR codes that tell listeners whether recording and sharing are welcome.")),
    h("ol", { id: "code-help" },
      h("li", {}, "Open SOWER on your iPhone."),
      h("li", {}, "Go to Settings › Community › your name › Link a browser."),
      h("li", {}, "Enter the code it shows. Codes last 5 minutes.")),
    h("label", { for: "code" }, "Code", input),
    error,
    h("div", { class: "form-actions" }, h("button", { class: "btn primary" }, "Sign in")));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    error.textContent = "";
    try {
      await api.signInWithCode(input.value);
      await loadChurches();
    } catch (err) {
      error.textContent = err.status === 401 || err.code === "not_found"
        ? "That code didn’t work. Codes expire after 5 minutes and work once; make a new one in the app."
        : errorText(err);
      input.focus();
    }
  });
  view.replaceChildren(form);
  input.focus();
}

// ---------- Churches ----------

async function loadChurches() {
  renderAccount();
  view.replaceChildren(h("p", { class: "muted" }, "Loading your churches…"));
  churches = await api.all("/v1/portal/churches");
  if (!churches.length) return renderClaim();
  church = churches.find((c) => c.id === church?.id) ?? churches[0];
  renderChurch();
}

function renderClaim(asAdditional = false) {
  const fields = {
    name: h("input", { id: "claim-name", required: true, maxlength: "120" }),
    website: h("input", { id: "claim-website", type: "url", required: true, placeholder: "https://" }),
    role: h("input", { id: "claim-role", required: true, maxlength: "80", placeholder: "Pastor, media lead, administrator…" }),
    evidence: h("textarea", { id: "claim-evidence", required: true, maxlength: "1000" }),
  };
  const form = h("form", { class: "panel stack" },
    h("div", { class: "page-head" },
      h("h1", { class: "display" }, asAdditional ? "Claim another church" : "Claim your church"),
      h("p", { class: "muted" }, "A SOWER moderator checks every claim before you can manage a church. Verification confirms who you are; it isn’t an endorsement of anything you publish.")),
    h("div", { class: "form-grid" },
      h("label", { for: "claim-name" }, "Church name", fields.name),
      h("label", { for: "claim-website" }, "Church website", fields.website),
      h("label", { for: "claim-role" }, "Your role", fields.role)),
    h("label", { for: "claim-evidence" }, "How can we confirm this?",
      h("span", { class: "hint" }, "For example, a staff page that lists you, or an email address on the church’s domain we can write to."),
      fields.evidence),
    h("div", { class: "form-actions" },
      h("button", { class: "btn primary" }, "Send claim"),
      asAdditional ? h("button", { class: "btn", type: "button", onclick: renderChurch }, "Cancel") : null));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await api.post("/v1/church-claims", {
        name: fields.name.value.trim(), website: fields.website.value.trim(),
        role: fields.role.value.trim(), evidence: fields.evidence.value.trim(),
      });
      view.replaceChildren(h("div", { class: "panel stack" },
        h("h1", { class: "display" }, "Claim sent"),
        h("p", {}, "A moderator will review it. Once it’s approved, sign in again and your church will be here."),
        h("div", { class: "form-actions" }, h("button", { class: "btn", onclick: loadChurches }, "Check again"))));
    } catch (err) {
      announce(errorText(err), "error");
    }
  });
  view.replaceChildren(form);
}

function renderChurch() {
  const tabs = [
    ["review", "Review"], ["sermons", "Sermons"], ["official", "Official audio"], ["services", "Service QR codes"], ["profile", "Church profile"],
  ];
  const picker = churches.length > 1
    ? h("label", { for: "church-picker" }, "Church",
        h("select", { id: "church-picker", onchange: (e) => { church = churches.find((c) => c.id === e.target.value); renderChurch(); } },
          churches.map((c) => h("option", { value: c.id, selected: c.id === church.id }, c.name))))
    : null;
  const tabBar = h("div", { class: "tabs", role: "tablist", "aria-label": "Church sections" },
    tabs.map(([id, label]) => h("button", {
      role: "tab", id: `tab-${id}`, "aria-selected": String(tab === id), "aria-controls": "panel",
      onclick: () => { tab = id; renderChurch(); },
    }, label)));
  const panel = h("section", { id: "panel", role: "tabpanel", "aria-labelledby": `tab-${tab}`, class: "stack" });
  view.replaceChildren(
    h("div", { class: "page-head" },
      h("h1", { class: "display" }, church.name),
      h("div", { class: "row" },
        church.verified ? h("span", { class: "tag lime ok" }, "Verified church") : h("span", { class: "tag warn" }, "Not verified yet"),
        church.fictional ? h("span", { class: "tag" }, "Fictional sample church") : null,
        h("button", { class: "btn link", onclick: () => renderClaim(true) }, "Claim another church"))),
    h("div", { class: "toolbar" }, tabBar, picker),
    panel);
  ({ review: renderReview, sermons: renderSermons, official: renderOfficial, services: renderServices, profile: renderProfile })[tab](panel);
}

// ---------- Review ----------

async function renderReview(panel) {
  panel.replaceChildren(h("p", { class: "muted" }, "Loading recordings…"));
  let rows;
  try {
    rows = await api.all(`/v1/portal/churches/${church.id}/publications`);
  } catch (err) { return panel.replaceChildren(h("div", { class: "notice error" }, errorText(err))); }
  const pending = rows.filter((p) => p.state === "pendingRights");
  const others = rows.filter((p) => p.state !== "pendingRights");
  panel.replaceChildren(
    h("p", { class: "muted" }, "Listeners can record your services for themselves. When they choose to share audio publicly, it waits here until you approve it. Approving lets anyone with SOWER listen."),
    pending.length
      ? h("div", { class: "items" }, pending.map((p) => reviewItem(p, true)))
      : h("div", { class: "panel quiet empty" }, h("strong", {}, "Nothing to review"), "Shared recordings from your services will appear here."),
    others.length ? h("h2", { class: "display", "aria-level": "2" }, "Earlier") : null,
    others.length ? h("div", { class: "items" }, others.map((p) => reviewItem(p, false))) : null);
}

function reviewItem(pub, actionable) {
  const review = pub.review ?? null;
  const player = h("div");
  const item = h("article", { class: "panel item" },
    h("div", { class: "item-head" },
      h("h3", {}, review?.title || "Shared recording"),
      h("span", { class: `tag ${pub.state === "published" ? "lime ok" : pub.state === "pendingRights" ? "coral warn" : ""}` }, STATE_LABEL[pub.state] ?? pub.state)),
    h("div", { class: "meta" },
      review?.preacher ? h("span", {}, review.preacher) : null,
      review?.serviceDate ? h("span", {}, formatDate(review.serviceDate)) : null,
      review?.primaryPassage ? h("span", {}, review.primaryPassage) : null,
      review?.audio ? h("span", {}, `Audio ${clock(review.audio.duration)}`) : h("span", {}, "No audio"),
      review?.rightsBasis ? h("span", {}, BASIS_LABEL[review.rightsBasis] ?? review.rightsBasis) : null,
      h("span", {}, `Shared ${formatDate(pub.createdAt)}`)),
    review?.summary ? h("p", {}, review.summary) : null,
    review?.checklist ? h("div", { class: "checklist", "aria-label": "What the listener checked before sharing" },
      checklistTag(review.checklist.musicReviewed, "Music checked"),
      checklistTag(review.checklist.prayerRequestsReviewed, "Prayer requests checked"),
      checklistTag(review.checklist.childrenReviewed, "Children checked"),
      checklistTag(review.checklist.privateTalkReviewed, "Private talk checked")) : null,
    player);
  if (pub.audioAssetID && actionable) {
    player.append(h("button", { class: "btn", onclick: async (e) => {
      e.target.disabled = true;
      try {
        const { url } = await api.post(`/v1/portal/churches/${church.id}/publications/${pub.id}/preview-url`);
        player.replaceChildren(h("audio", { controls: true, src: url, preload: "metadata", "aria-label": "Listen to the shared recording" }));
      } catch (err) {
        player.replaceChildren(h("p", { class: "faint" }, err.status === 404 ? "Listening before approval isn’t available yet." : errorText(err)));
      }
    } }, "Listen first"));
  }
  if (actionable) {
    item.append(h("div", { class: "form-actions" },
      h("button", { class: "btn primary", onclick: () => decide(pub, "approve") }, "Approve for everyone"),
      h("button", { class: "btn danger", onclick: () => decide(pub, "reject") }, "Don’t publish")));
  }
  return item;
}

function checklistTag(ok, label) {
  return h("span", { class: `tag ${ok ? "ok" : "warn"}` }, ok ? label : label.replace("checked", "not checked"));
}

async function decide(pub, decision) {
  const reason = await askReason(decision === "approve"
    ? { title: "Approve recording", detail: "Anyone with SOWER will be able to listen. You can request removal later.", confirmLabel: "Approve" }
    : { title: "Don’t publish", detail: "The listener keeps their private recording. Their card stays, without public audio.", confirmLabel: "Don’t publish", danger: true });
  if (!reason) return;
  try {
    await api.post(`/v1/portal/churches/${church.id}/publications/${pub.id}/decision`, { decision, reason });
    announce(decision === "approve" ? "Approved. The recording is now published." : "Marked as not published.", "ok");
    renderChurch();
  } catch (err) { announce(errorText(err), "error"); }
}

// ---------- Sermons ----------

async function renderSermons(panel) {
  panel.replaceChildren(h("p", { class: "muted" }, "Loading sermons…"));
  let sermons;
  try { sermons = await api.all(`/v1/churches/${church.id}/sermons`); }
  catch (err) { return panel.replaceChildren(h("div", { class: "notice error" }, errorText(err))); }
  if (!sermons.length) {
    return panel.replaceChildren(h("div", { class: "panel quiet empty" }, h("strong", {}, "No published sermons yet"), "Approved recordings and your official audio will be listed here."));
  }
  panel.replaceChildren(
    h("p", { class: "muted" }, "Correct anything listeners got wrong. Removing audio takes effect immediately; cards and listening history stay intact."),
    h("div", { class: "table-wrap" },
      h("table", {},
        h("thead", {}, h("tr", {}, ["Sermon", "Date", "Passage", "Labels", ""].map((t) => h("th", { scope: "col" }, t)))),
        h("tbody", {}, sermons.map((s) => h("tr", {},
          h("td", {}, h("strong", {}, s.title), h("div", { class: "faint" }, s.preacher)),
          h("td", { class: "num" }, formatDate(s.serviceDate)),
          h("td", {}, s.primaryPassage),
          h("td", {}, h("div", { class: "checklist" }, (s.trustLabels ?? []).map((l) => h("span", { class: "tag" }, l)))),
          h("td", {}, h("div", { class: "row" },
            h("button", { class: "btn link", onclick: () => correct(s) }, "Correct details"),
            s.audioAvailable ? h("button", { class: "btn link", onclick: () => requestRemoval(s) }, "Remove audio") : null))))))));
}

function correct(sermon) {
  const f = {
    title: h("input", { id: "c-title", value: sermon.title, required: true }),
    preacher: h("input", { id: "c-preacher", value: sermon.preacher, required: true }),
    passage: h("input", { id: "c-passage", value: sermon.primaryPassage }),
    date: h("input", { id: "c-date", type: "date", value: (sermon.serviceDate ?? "").slice(0, 10) }),
  };
  const dialog = h("dialog", { "aria-labelledby": "c-head" },
    h("form", { method: "dialog", class: "stack" },
      h("h2", { id: "c-head", class: "display dialog-title" }, "Correct details"),
      h("p", { class: "muted" }, "Corrections from your church mark the sermon as church verified."),
      h("label", { for: "c-title" }, "Title", f.title),
      h("label", { for: "c-preacher" }, "Preacher", f.preacher),
      h("label", { for: "c-passage" }, "Scripture passage", f.passage),
      h("label", { for: "c-date" }, "Service date", f.date),
      h("div", { class: "form-actions" }, h("button", { class: "btn primary", value: "ok" }, "Save"), h("button", { class: "btn", value: "cancel", formnovalidate: true }, "Cancel"))));
  document.body.append(dialog);
  dialog.addEventListener("close", async () => {
    dialog.remove();
    if (dialog.returnValue !== "ok") return;
    try {
      await api.post(`/v1/portal/churches/${church.id}/sermons/${sermon.id}/correct`, {
        title: f.title.value.trim(), preacher: f.preacher.value.trim(), primaryPassage: f.passage.value.trim(),
        serviceDate: f.date.value ? new Date(`${f.date.value}T12:00:00Z`).toISOString() : undefined,
      });
      announce("Saved. The sermon is now church verified.", "ok");
      renderChurch();
    } catch (err) { announce(errorText(err), "error"); }
  });
  dialog.showModal();
}

async function requestRemoval(sermon) {
  const reason = await askReason({ title: "Remove audio", detail: `Playback of “${sermon.title}” stops for everyone right away. Listeners keep the sermon and their cards.`, confirmLabel: "Remove audio", danger: true });
  if (!reason) return;
  try {
    await api.post(`/v1/portal/churches/${church.id}/removals`, { sermonID: sermon.id, reason });
    announce("Audio removed. A moderator has been notified.", "ok");
    renderChurch();
  } catch (err) { announce(errorText(err), "error"); }
}

// ---------- Official audio ----------

function renderOfficial(panel) {
  const f = {
    title: h("input", { id: "o-title", required: true, maxlength: "140" }),
    preacher: h("input", { id: "o-preacher", required: true, maxlength: "120" }),
    service: h("input", { id: "o-service", maxlength: "80", placeholder: "Sunday 10 AM" }),
    date: h("input", { id: "o-date", type: "date", required: true }),
    passage: h("input", { id: "o-passage", required: true, maxlength: "80", placeholder: "Mark 4:35–41" }),
    type: h("select", { id: "o-type" }, SERMON_TYPES.map((t) => h("option", { value: t }, t[0].toUpperCase() + t.slice(1)))),
    themes: h("input", { id: "o-themes", placeholder: "Fear, Trust" }),
    summary: h("textarea", { id: "o-summary", maxlength: "280" }),
    reflection: h("input", { id: "o-reflection", maxlength: "160" }),
    file: h("input", { id: "o-file", type: "file", accept: "audio/mp4,audio/x-m4a,.m4a", required: true }),
  };
  const checks = ["musicReviewed", "prayerRequestsReviewed", "childrenReviewed", "privateTalkReviewed"].map((key, i) =>
    h("label", { class: "check", for: `o-check-${i}` }, h("input", { type: "checkbox", id: `o-check-${i}`, name: key, required: true }),
      ["Licensed music is trimmed or we hold the rights", "Prayer requests and personal stories are removed", "Children’s voices are removed or permitted", "No private conversations remain"][i]));
  const progress = h("div", { class: "progress", hidden: true, role: "progressbar", "aria-label": "Upload progress", "aria-valuemin": "0", "aria-valuemax": "100" }, h("div"));
  const status = h("p", { class: "faint", role: "status" });
  const submit = h("button", { class: "btn primary" }, "Publish official audio");
  const form = h("form", { class: "split" },
    h("div", { class: "panel stack" },
      h("h2", { class: "display dialog-title" }, "Sermon"),
      h("div", { class: "form-grid" },
        h("label", { for: "o-title" }, "Title", f.title),
        h("label", { for: "o-preacher" }, "Preacher", f.preacher),
        h("label", { for: "o-service" }, "Service", f.service),
        h("label", { for: "o-date" }, "Date", f.date),
        h("label", { for: "o-passage" }, "Scripture passage", f.passage),
        h("label", { for: "o-type" }, "Type", f.type)),
      h("label", { for: "o-themes" }, "Themes", h("span", { class: "hint" }, "Separate with commas."), f.themes),
      h("label", { for: "o-summary" }, "The big idea", h("span", { class: "hint" }, "One or two sentences listeners will see on the card."), f.summary),
      h("label", { for: "o-reflection" }, "A question to reflect on", f.reflection)),
    h("div", { class: "panel stack" },
      h("h2", { class: "display dialog-title" }, "Audio"),
      h("label", { for: "o-file" }, "Recording (.m4a, AAC)", h("span", { class: "hint" }, "Up to 200 MB and 3 hours. This becomes the version everyone hears; listeners who recorded the service can choose whether to switch."), f.file),
      h("fieldset", {}, h("legend", {}, "Before publishing"), checks),
      progress, status,
      h("div", { class: "form-actions" }, submit)));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const file = f.file.files[0];
    if (!file) return;
    submit.disabled = true;
    try {
      status.textContent = "Reading the file…";
      const bytes = await file.arrayBuffer();
      const checksum = await sha256Hex(bytes);
      const duration = await audioDuration(file);
      const body = {
        title: f.title.value.trim(), preacher: f.preacher.value.trim(), churchID: church.id,
        service: f.service.value.trim() || null, serviceDate: new Date(`${f.date.value}T12:00:00Z`).toISOString(),
        primaryPassage: f.passage.value.trim(), sermonType: f.type.value,
        themes: f.themes.value.split(",").map((t) => t.trim()).filter(Boolean),
        city: church.city, region: church.region, country: church.country,
        summary: f.summary.value.trim() || null, reflectionPrompt: f.reflection.value.trim() || null, reviewed: true,
        checklist: Object.fromEntries(checks.map((c) => [c.querySelector("input").name, c.querySelector("input").checked])),
        rightsBasis: "official",
        audio: { byteCount: file.size, duration, checksumSHA256: checksum, contentType: "audio/mp4", trimStart: 0, trimEnd: duration, sourceChecksumSHA256: checksum },
      };
      status.textContent = "Starting upload…";
      const result = await api.post(`/v1/portal/churches/${church.id}/official-audio`, body);
      progress.hidden = false;
      await upload(result.uploadURL, bytes, (pct) => {
        progress.firstChild.style.width = `${pct}%`;
        progress.setAttribute("aria-valuenow", String(Math.round(pct)));
        status.textContent = `Uploading… ${Math.round(pct)}%`;
      });
      status.textContent = "Checking the audio…";
      await api.post(`/v1/publications/${result.publicationID}/complete`);
      announce(`Published “${body.title}”. It’s now the official audio for this sermon.`, "ok");
      form.reset();
      progress.hidden = true;
      status.textContent = "";
    } catch (err) {
      status.textContent = "";
      announce(err?.code === "invalid_audio"
        ? "That file isn’t AAC audio in an .m4a container. Export it as .m4a (AAC) and try again."
        : errorText(err), "error");
    } finally {
      submit.disabled = false;
    }
  });
  panel.replaceChildren(form);
}

function audioDuration(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const audio = new Audio();
    audio.preload = "metadata";
    audio.onloadedmetadata = () => { URL.revokeObjectURL(url); resolve(Math.round(audio.duration * 100) / 100); };
    audio.onerror = () => { URL.revokeObjectURL(url); reject(new ApiError(422, "invalid_audio")); };
    audio.src = url;
  });
}

function upload(url, bytes, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", url);
    xhr.setRequestHeader("Content-Type", "audio/mp4");
    xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress((e.loaded / e.total) * 100); };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) return resolve();
      let message;
      try { message = JSON.parse(xhr.responseText)?.error?.message; } catch { /* not JSON */ }
      reject(new ApiError(xhr.status, "upload_failed", message || "The upload didn’t finish. Try again."));
    };
    xhr.onerror = () => reject(new ApiError(0, "offline", "The upload was interrupted. Check your connection and try again."));
    xhr.send(bytes);
  });
}

// ---------- Service QR codes ----------

async function renderServices(panel) {
  const now = new Date();
  const local = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  const f = {
    service: h("input", { id: "s-service", required: true, maxlength: "80", placeholder: "Sunday 10 AM" }),
    startsAt: h("input", { id: "s-start", type: "datetime-local", required: true, value: local(now) }),
    expiresAt: h("input", { id: "s-end", type: "datetime-local", required: true, value: local(new Date(now.getTime() + 6 * 3600 * 1000)) }),
    recording: h("input", { id: "s-rec", type: "checkbox", checked: true }),
    sharing: h("input", { id: "s-share", type: "checkbox" }),
    review: h("input", { id: "s-review", type: "checkbox", checked: true }),
  };
  const form = h("form", { class: "panel stack" },
    h("h2", { class: "display dialog-title" }, "New service code"),
    h("p", { class: "muted" }, "Print it or show it on screen. When a listener scans it, SOWER tells them what your church allows for this service. It’s a signal, not blanket permission, and you can revoke it any time."),
    h("div", { class: "form-grid" },
      h("label", { for: "s-service" }, "Service", f.service),
      h("label", { for: "s-start" }, "Starts", f.startsAt),
      h("label", { for: "s-end" }, "Code expires", f.expiresAt)),
    h("label", { class: "check", for: "s-rec" }, f.recording, "Listeners may record this service for themselves"),
    h("label", { class: "check", for: "s-share" }, f.sharing, "Listeners may share recordings publicly in SOWER"),
    h("label", { class: "check", for: "s-review" }, f.review, "We review shared recordings before anyone can listen"),
    h("div", { class: "form-actions" }, h("button", { class: "btn primary" }, "Create code")));
  f.sharing.addEventListener("change", () => { if (!f.sharing.checked) f.review.checked = true; });
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const result = await api.post(`/v1/portal/churches/${church.id}/services`, {
        service: f.service.value.trim(), startsAt: new Date(f.startsAt.value).toISOString(), expiresAt: new Date(f.expiresAt.value).toISOString(),
        recordingAllowed: f.recording.checked, publicSharingAllowed: f.sharing.checked, reviewRequired: f.review.checked,
      });
      announce("Code created.", "ok");
      window.open(result.printURL, "_blank", "noopener");
      renderChurch();
    } catch (err) { announce(errorText(err), "error"); }
  });
  const list = h("div", {}, h("p", { class: "muted" }, "Loading codes…"));
  panel.replaceChildren(h("div", { class: "split" }, form, list));
  try {
    const services = await api.all(`/v1/portal/churches/${church.id}/services`);
    list.replaceChildren(services.length
      ? h("div", { class: "items" }, services.map((s) => h("article", { class: "panel item" },
          h("div", { class: "item-head" }, h("h3", {}, s.service),
            s.revoked ? h("span", { class: "tag coral" }, "Revoked") : new Date(s.expiresAt) < new Date() ? h("span", { class: "tag" }, "Expired") : h("span", { class: "tag lime ok" }, "Active")),
          h("div", { class: "meta" }, h("span", {}, `Starts ${formatDate(s.startsAt, true)}`), h("span", {}, `Expires ${formatDate(s.expiresAt, true)}`)),
          h("div", { class: "checklist" },
            h("span", { class: "tag" }, s.recordingAllowed ? "Recording welcome" : "No recording"),
            h("span", { class: "tag" }, s.publicSharingAllowed ? "Sharing allowed" : "No public sharing"),
            s.publicSharingAllowed ? h("span", { class: "tag" }, s.reviewRequired ? "Church reviews first" : "No review") : null),
          h("div", { class: "row" },
            h("a", { class: "btn", href: `/portal/services/${encodeURIComponent(s.id)}/print`, target: "_blank", rel: "noopener" }, "Print"),
            s.revoked ? null : h("button", { class: "btn link", onclick: () => revoke(s) }, "Revoke")))))
      : h("div", { class: "panel quiet empty" }, h("strong", {}, "No codes yet"), "Create one for your next service."));
  } catch (err) { list.replaceChildren(h("div", { class: "notice error" }, errorText(err))); }
}

async function revoke(service) {
  const reason = await askReason({ title: "Revoke code", detail: "Recordings shared with this code lose their public audio until you approve them again.", confirmLabel: "Revoke", danger: true });
  if (!reason) return;
  try {
    await api.post(`/v1/portal/churches/${church.id}/services/${service.id}/revoke`);
    announce("Code revoked.", "ok");
    renderChurch();
  } catch (err) { announce(errorText(err), "error"); }
}

// ---------- Profile ----------

function renderProfile(panel) {
  const f = {
    name: h("input", { id: "p-name", value: church.name, required: true }),
    website: h("input", { id: "p-web", type: "url", value: church.website ?? "" }),
    city: h("input", { id: "p-city", value: church.city ?? "" }),
    region: h("input", { id: "p-region", value: church.region ?? "" }),
    country: h("input", { id: "p-country", value: church.country ?? "", maxlength: "2", placeholder: "US" }),
  };
  const credit = (value, label, hint) => h("label", { class: "check", for: `p-credit-${value}` },
    h("input", { type: "radio", name: "credit", id: `p-credit-${value}`, value, checked: church.creditPolicy === value }),
    h("span", {}, h("strong", {}, label), h("br"), h("span", { class: "hint" }, hint)));
  const form = h("form", { class: "panel stack" },
    h("p", { class: "muted" }, "This is what listeners see. SOWER shows your church’s city on its map, never a street address."),
    h("div", { class: "form-grid" },
      h("label", { for: "p-name" }, "Church name", f.name),
      h("label", { for: "p-web" }, "Website", f.website),
      h("label", { for: "p-city" }, "City", f.city),
      h("label", { for: "p-region" }, "State or region", f.region),
      h("label", { for: "p-country" }, "Country code", f.country)),
    h("fieldset", {}, h("legend", {}, "Credit for listener recordings"),
      credit("named", "Show their display name", "Listeners who shared a recording you approved are credited by name."),
      credit("anonymous", "Keep contributors anonymous", "Recordings show “Shared by a listener”.")),
    h("div", { class: "form-actions" }, h("button", { class: "btn primary" }, "Save profile")));
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await api.patch(`/v1/portal/churches/${church.id}`, {
        name: f.name.value.trim(), website: f.website.value.trim() || undefined,
        city: f.city.value.trim() || null, region: f.region.value.trim() || null, country: f.country.value.trim().toUpperCase() || null,
        creditPolicy: form.querySelector("input[name=credit]:checked")?.value ?? church.creditPolicy,
      });
      announce("Profile saved.", "ok");
      await loadChurches();
    } catch (err) { announce(errorText(err), "error"); }
  });
  panel.replaceChildren(form);
}

start();
