"use strict";
// Unit catalog UI (TASK-037). Vanilla JS, no build step, no network except the local API
// (and thumbnails of AI image candidates, loaded straight from their https host).

const app = document.getElementById("app");
let catalog = { classes: [], factions: [], units: [], views: [], statuses: [], mobilities: [] };
let cleanup = null; // called when leaving a screen
const filters = { faction: "", cls: "", status: "", q: "" };
let ai = { available: false, hint: "" }; // GET /api/ai: can the server run Claude Code jobs?

// ---------------------------------------------------------------- helpers
function h(tag, props, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "text") el.textContent = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "value") el.value = v;
    else if (k === "checked" || k === "disabled" || k === "selected" || k === "hidden") el[k] = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return el;
}

async function api(method, url, body) {
  const opts = { method, headers: {} };
  if (method !== "GET") opts.headers["Content-Type"] = "application/json";
  if (body !== undefined) opts.body = JSON.stringify(body);
  const resp = await fetch(url, opts);
  let data = null;
  try { data = await resp.json(); } catch (e) { data = null; }
  if (!resp.ok) {
    const err = new Error("request failed");
    err.errors = (data && data.errors) || [{ field: "request", message: "HTTP " + resp.status }];
    err.status = resp.status;
    throw err;
  }
  return data;
}

function errText(err) {
  return (err.errors || [{ field: "", message: String(err) }]).map((e) => (e.field ? e.field + ": " : "") + e.message).join("\n");
}

function debounce(fn, ms) {
  let t = null;
  const wrapped = (...a) => { clearTimeout(t); t = setTimeout(() => { t = null; fn(...a); }, ms); };
  wrapped.flush = () => { if (t !== null) { clearTimeout(t); t = null; fn(); return true; } return false; };
  wrapped.pending = () => t !== null;
  return wrapped;
}

function slugify(s) { return s.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 48).replace(/_+$/, ""); }
function label(map, id, key) { const f = map.find((x) => x.id === id); return f ? f[key] : id; }
function factionById(id) { return catalog.factions.find((f) => f.id === id); }
function fileUrl(unitId, file, bust) { return "/files/units/" + encodeURIComponent(unitId) + "/" + encodeURIComponent(file) + (bust ? "?v=" + bust : ""); }
function pretty(s) { return s.replace(/_/g, " "); }

function factionChip(id) {
  const f = factionById(id);
  return h("span", { class: "chip" }, h("i", { class: "dot", style: "background:" + (f ? f.color : "#888") }), f ? f.name : id);
}

function completenessBar(v) {
  const pct = Math.round(v * 100);
  return h("span", { title: pct + "%" }, h("span", { class: "bar " + (pct < 35 ? "low" : pct < 70 ? "mid" : "") }, h("i", { style: "width:" + pct + "%" })), " ", h("span", { class: "mono muted", text: pct + "%" }));
}

function openModal(title, fields, onSubmit, submitLabel) {
  const root = document.getElementById("modal-root");
  const inputs = {};
  const err = h("div", { class: "errors" });
  const close = () => { root.textContent = ""; };
  const body = fields.map((f) => {
    if (f.checkbox) {
      const cb = h("input", { type: "checkbox", checked: !!f.value });
      inputs[f.key] = cb;
      return h("label", { class: "check-row" }, cb, f.label);
    }
    const input = f.options
      ? h("select", {}, f.options.map((o) => h("option", { value: o.value, text: o.label })))
      : h("input", { type: "text", value: f.value || "", placeholder: f.placeholder || "" });
    inputs[f.key] = input;
    if (f.onInput) input.addEventListener("input", () => f.onInput(input, inputs));
    return h("div", { class: "field" }, h("label", { text: f.label }), input);
  });
  const submit = async () => {
    const values = {};
    for (const k of Object.keys(inputs)) values[k] = inputs[k].type === "checkbox" ? inputs[k].checked : inputs[k].value;
    try { await onSubmit(values); close(); } catch (e) { err.textContent = errText(e); }
  };
  const bg = h("div", { class: "modal-bg", onclick: (e) => { if (e.target === bg) close(); } },
    h("div", { class: "modal" },
      h("h2", { text: title }), body, err,
      h("div", { class: "row" }, h("button", { class: "primary", text: submitLabel || "Create", onclick: submit }), h("button", { text: "Cancel", onclick: close }))));
  root.textContent = "";
  root.append(bg);
  bg.addEventListener("keydown", (e) => { if (e.key === "Enter") submit(); if (e.key === "Escape") close(); });
  const first = bg.querySelector("input,select");
  if (first) first.focus();
}

function showLightbox(src) {
  const lb = document.getElementById("lightbox");
  lb.textContent = "";
  lb.append(h("img", { src }));
  lb.hidden = false;
  lb.onclick = () => { lb.hidden = true; lb.textContent = ""; };
}
document.addEventListener("keydown", (e) => { if (e.key === "Escape") { const lb = document.getElementById("lightbox"); lb.hidden = true; } });

async function reloadCatalog() {
  catalog = await api("GET", "/api/catalog");
  try { ai = await api("GET", "/api/ai"); } catch (e) { ai = { available: false, hint: errText(e) }; }
}

async function startJob(kind, unitId, faction) {
  return api("POST", "/api/jobs", { kind, unit_id: unitId, faction: faction || "" });
}
const ACTIVE_JOB = ["queued", "running"];
function jobBadge(state) { return h("span", { class: "badge job-" + state, text: state }); }
function fmtTime(t) { return t ? new Date(t * 1000).toLocaleTimeString() : ""; }
function fmtDuration(j) {
  if (!j.started) return "";
  const s = Math.round((j.finished || Date.now() / 1000) - j.started);
  return Math.floor(s / 60) + "m " + (s % 60) + "s";
}

// Nav badge with the number of queued/running jobs.
async function refreshJobCount() {
  const el = document.getElementById("jobs-count");
  if (!el) return;
  try {
    const n = (await api("GET", "/api/jobs")).jobs.filter((j) => ACTIVE_JOB.includes(j.state)).length;
    el.textContent = n ? String(n) : "";
  } catch (e) { el.textContent = ""; }
}
setInterval(refreshJobCount, 4000);

// ---------------------------------------------------------------- routing
async function route() {
  if (cleanup) { try { await cleanup(); } catch (e) { /* ignore */ } cleanup = null; }
  const parts = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  document.querySelectorAll("[data-nav]").forEach((a) => a.classList.toggle("active", a.dataset.nav === (parts[0] === "classes" ? "classes" : parts[0] === "jobs" || parts[0] === "job" ? "jobs" : "overview")));
  app.textContent = "";
  refreshJobCount();
  try {
    await reloadCatalog();
    if (parts[0] === "unit" && parts[1]) await unitScreen(parts[1]);
    else if (parts[0] === "faction" && parts[1]) factionScreen(parts[1]);
    else if (parts[0] === "classes") classesScreen();
    else if (parts[0] === "jobs") await jobsScreen();
    else if (parts[0] === "job" && parts[1]) await jobScreen(parts[1]);
    else overviewScreen();
  } catch (e) {
    app.append(h("div", { class: "panel" }, h("h2", { text: "Error" }), h("div", { class: "errors", text: errText(e) }), h("p", {}, h("a", { href: "#/", text: "Back to overview" }))));
  }
}
window.addEventListener("hashchange", route);
window.addEventListener("beforeunload", (e) => { if (window.__pendingSave && window.__pendingSave()) { e.preventDefault(); e.returnValue = ""; } });

// ---------------------------------------------------------------- overview
function overviewScreen() {
  const tableBox = h("div");
  const restoreBox = h("div", { class: "errors" });
  const missingTotal = catalog.units.reduce((n, u) => n + (u.missing_images || 0), 0);
  const restoreAll = async () => {
    restoreBox.textContent = "Downloading...";
    try {
      const res = await api("POST", "/api/images/restore", {});
      const failed = res.reports.flatMap((r) => r.failed.map((f) => r.unit_id + "/" + f.file + ": " + f.message));
      if (failed.length) { await reloadCatalog(); restoreBox.textContent = "Not restored:\n" + failed.join("\n"); }
      else route();
    } catch (e) { restoreBox.textContent = errText(e); }
  };
  const render = () => {
    const q = filters.q.trim().toLowerCase();
    const rows = catalog.units.filter((u) =>
      (!filters.faction || u.operators.includes(filters.faction)) &&
      (!filters.cls || u.class === filters.cls) &&
      (!filters.status || u.status === filters.status) &&
      (!q || (u.real_name + " " + u.id).toLowerCase().includes(q)));
    tableBox.textContent = "";
    if (!rows.length) { tableBox.append(h("p", { class: "muted", text: catalog.units.length ? "No units match the filters." : "No units yet - create the first one." })); return; }
    tableBox.append(h("table", {},
      h("thead", {}, h("tr", {}, ["Real name", "Class", "Operators", "Images", "Completeness", "Status"].map((t) => h("th", { text: t })))),
      h("tbody", {}, rows.map((u) => h("tr", { class: "clickable", onclick: () => { location.hash = "#/unit/" + encodeURIComponent(u.id); } },
        h("td", {}, h("strong", { text: u.real_name }), " ", h("span", { class: "mono muted", text: u.id })),
        h("td", { text: label(catalog.classes, u.class, "label") }),
        h("td", {}, u.operators.map(factionChip)),
        h("td", { class: "num", text: u.image_count }),
        h("td", {}, completenessBar(u.completeness)),
        h("td", {}, h("span", { class: "badge " + u.status, text: u.status })))))));
  };
  const select = (key, opts, ph) => h("select", { onchange: (e) => { filters[key] = e.target.value; render(); } },
    h("option", { value: "", text: ph }), opts.map((o) => h("option", { value: o.value, text: o.label, selected: filters[key] === o.value })));
  app.append(
    h("div", { class: "panel" },
      h("div", { class: "row", style: "margin-bottom:10px" },
        h("h1", { style: "margin:0;flex:1", text: "Units (" + catalog.units.length + ")" }),
        missingTotal ? h("button", { text: "Restore missing images (" + missingTotal + ")", title: "Image files are not in git; this downloads them again from their source URLs", onclick: restoreAll }) : null,
        h("button", { class: "primary", text: "New unit", onclick: newUnitDialog })),
      restoreBox,
      h("div", { class: "row", style: "margin-bottom:10px" },
        h("input", { type: "search", placeholder: "Search name or id...", value: filters.q, style: "max-width:260px", oninput: (e) => { filters.q = e.target.value; render(); } }),
        select("faction", catalog.factions.map((f) => ({ value: f.id, label: f.name })), "All factions"),
        select("cls", catalog.classes.map((c) => ({ value: c.id, label: c.label })), "All classes"),
        select("status", catalog.statuses.map((s) => ({ value: s, label: s })), "All statuses")),
      tableBox),
    h("div", { class: "panel" },
      h("div", { class: "row", style: "margin-bottom:10px" },
        h("h1", { style: "margin:0;flex:1", text: "Factions" }),
        h("button", { text: "New faction", onclick: newFactionDialog })),
      h("table", {}, h("thead", {}, h("tr", {}, ["Faction", "ISO", "Colour", "Camo", "Units"].map((t) => h("th", { text: t })))),
        h("tbody", {}, catalog.factions.map((f) => h("tr", { class: "clickable", onclick: () => { location.hash = "#/faction/" + encodeURIComponent(f.id); } },
          h("td", {}, h("strong", { text: f.name }), " ", h("span", { class: "mono muted", text: f.id })),
          h("td", { class: "mono", text: f.iso_code }),
          h("td", {}, h("span", { class: "swatch", style: "background:" + f.color })),
          h("td", {}, f.camo.map((c) => h("span", { class: "swatch", style: "background:" + c + ";margin-right:3px" }))),
          h("td", { class: "num", text: catalog.units.filter((u) => u.operators.includes(f.id)).length })))))));
  render();
}

function newUnitDialog() {
  openModal("New unit", [
    { key: "real_name", label: "Real name (shown in game)", placeholder: "Leopard 2A4", onInput: (input, inputs) => { if (!inputs.id.dataset.touched) inputs.id.value = slugify(input.value); } },
    { key: "id", label: "Id (also the file name of stats and model)", onInput: (input) => { input.dataset.touched = "1"; } },
    { key: "class", label: "Class", options: catalog.classes.map((c) => ({ value: c.id, label: c.label })) },
    { key: "operator", label: "Operator", options: [{ value: "", label: "(none yet)" }].concat(catalog.factions.map((f) => ({ value: f.id, label: f.name }))) },
  ].concat(ai.available ? [{ key: "research", label: "Research the unit with AI (web search; you verify the result)", checkbox: true, value: true }] : []), async (v) => {
    const body = { real_name: v.real_name, id: v.id, class: v.class, operators: v.operator ? [v.operator] : [] };
    const created = await api("POST", "/api/units", body);
    if (v.research) await startJob("research", created.unit.id);
    location.hash = "#/unit/" + encodeURIComponent(created.unit.id);
  });
}

function newFactionDialog() {
  openModal("New faction", [
    { key: "name", label: "Name (English)", onInput: (input, inputs) => { if (!inputs.id.dataset.touched) inputs.id.value = slugify(input.value); } },
    { key: "id", label: "Id", onInput: (input) => { input.dataset.touched = "1"; } },
    { key: "iso", label: "ISO code (2-3 capitals)" },
  ], async (v) => {
    const f = { id: v.id, name: v.name, iso_code: v.iso.toUpperCase(), color: "#888888", camo: ["#4b5320", "#3b2f22", "#1e1f1a"], vest_color: "#4f5934", notes: "" };
    await api("POST", "/api/factions", f);
    location.hash = "#/faction/" + encodeURIComponent(v.id);
  });
}

// ---------------------------------------------------------------- faction editor
function factionScreen(id) {
  const orig = factionById(id);
  if (!orig) throw { errors: [{ field: "id", message: "faction not found" }] };
  const f = JSON.parse(JSON.stringify(orig));
  const state = h("span", { class: "savestate saved", text: "saved" });
  const errBox = h("div", { class: "errors" });
  const preview = h("div", { class: "camo-preview" });
  const drawPreview = () => {
    preview.textContent = "";
    preview.style.background = f.camo[0];
    const blobs = [[5, 10, 90, 60, 1], [40, 40, 110, 70, 2], [70, 5, 80, 50, 1], [15, 55, 100, 55, 2], [60, 60, 90, 50, 0], [25, 20, 70, 45, 0], [80, 40, 70, 55, 2]];
    for (const [x, y, w, hh, ci] of blobs) preview.append(h("div", { class: "blob", style: `left:${x}%;top:${y}%;width:${w}px;height:${hh}px;background:${f.camo[ci]}` }));
    preview.append(h("div", { style: `position:absolute;right:12px;bottom:10px;padding:2px 8px;border-radius:3px;background:${f.vest_color};font:12px var(--mono);color:#ebe8df`, text: "vest" }));
    preview.append(h("div", { style: `position:absolute;left:12px;bottom:10px;width:14px;height:14px;border-radius:50%;background:${f.color}` }));
  };
  const save = debounce(async () => {
    state.className = "savestate saving"; state.textContent = "saving...";
    try {
      const saved = await api("PUT", "/api/factions/" + encodeURIComponent(id), f);
      Object.assign(f, saved);
      errBox.textContent = ""; state.className = "savestate saved"; state.textContent = "saved";
    } catch (e) { state.className = "savestate error"; state.textContent = "not saved"; errBox.textContent = errText(e); }
  }, 500);
  window.__pendingSave = save.pending;
  cleanup = () => { save.flush(); window.__pendingSave = null; };
  const changed = () => { state.className = "savestate saving"; state.textContent = "editing..."; drawPreview(); save(); };
  const colorField = (lbl, get, set) => {
    const hex = h("span", { class: "mono muted", text: get() });
    const input = h("input", { type: "color", value: get(), oninput: (e) => { set(e.target.value); hex.textContent = e.target.value; changed(); } });
    return h("div", { class: "field" }, h("label", { text: lbl }), h("div", { class: "row" }, input, hex));
  };
  const text = (lbl, key, extra) => h("div", { class: "field" }, h("label", { text: lbl }), h("input", Object.assign({ type: "text", value: f[key] || "", oninput: (e) => { f[key] = key === "iso_code" ? e.target.value.toUpperCase() : e.target.value; changed(); } }, extra || {})));
  app.append(
    h("div", { class: "editor-head" }, h("a", { href: "#/", text: "< Overview" }), h("h1", { text: "Faction: " + f.name }), state),
    h("div", { class: "panel" },
      h("div", { class: "grid" },
        text("Name (English)", "name"), text("ISO code", "iso_code", { maxlength: 3 }),
        colorField("UI colour", () => f.color, (v) => { f.color = v; }),
        colorField("Vest colour", () => f.vest_color, (v) => { f.vest_color = v; }),
        [0, 1, 2].map((i) => colorField("Camo " + (i + 1), () => f.camo[i], (v) => { f.camo[i] = v; })),
        h("div", { class: "field wide" }, h("label", { text: "Notes" }), h("textarea", { oninput: (e) => { f.notes = e.target.value; changed(); } }, f.notes || ""))),
      errBox),
    h("div", { class: "panel" }, h("h2", { text: "Camo swatch preview" }), preview));
  drawPreview();
}

// ---------------------------------------------------------------- classes editor
function classesScreen() {
  const classes = JSON.parse(JSON.stringify(catalog.classes));
  const state = h("span", { class: "savestate saved", text: "saved" });
  const errBox = h("div", { class: "errors" });
  const body = h("div");
  const save = debounce(async () => {
    state.className = "savestate saving"; state.textContent = "saving...";
    try { await api("PUT", "/api/classes", { classes }); errBox.textContent = ""; state.className = "savestate saved"; state.textContent = "saved"; }
    catch (e) { state.className = "savestate error"; state.textContent = "not saved"; errBox.textContent = errText(e); }
  }, 600);
  window.__pendingSave = save.pending;
  cleanup = () => { save.flush(); window.__pendingSave = null; };
  const changed = () => { state.className = "savestate saving"; state.textContent = "editing..."; save(); };
  const render = () => {
    body.textContent = "";
    body.append(h("table", {},
      h("thead", {}, h("tr", {}, ["Id", "Label", "Mobility", "Required views"].map((t) => h("th", { text: t })))),
      h("tbody", {}, classes.map((c) => h("tr", {},
        h("td", { class: "mono", text: c.id }),
        h("td", {}, h("input", { type: "text", value: c.label, oninput: (e) => { c.label = e.target.value; changed(); } })),
        h("td", {}, h("select", { onchange: (e) => { c.mobility = e.target.value; changed(); } }, catalog.mobilities.map((m) => h("option", { value: m, text: m, selected: c.mobility === m })))),
        h("td", {}, h("div", { class: "multi" }, catalog.views.map((v) => {
          const on = (c.required_views || []).includes(v);
          const cb = h("input", { type: "checkbox", checked: on });
          const lab = h("label", { class: on ? "on" : "" }, cb, pretty(v));
          cb.addEventListener("change", () => {
            const s = new Set(c.required_views || []);
            if (cb.checked) s.add(v); else s.delete(v);
            c.required_views = catalog.views.filter((x) => s.has(x));
            lab.classList.toggle("on", cb.checked); changed();
          });
          return lab;
        }))))))));
  };
  app.append(
    h("div", { class: "editor-head" }, h("h1", { text: "Unit classes" }), h("button", { text: "Add class", onclick: () => openModal("New class", [
      { key: "label", label: "Label", onInput: (input, inputs) => { if (!inputs.id.dataset.touched) inputs.id.value = slugify(input.value); } },
      { key: "id", label: "Id", onInput: (input) => { input.dataset.touched = "1"; } },
      { key: "mobility", label: "Mobility", options: catalog.mobilities.map((m) => ({ value: m, label: m })) },
    ], async (v) => { classes.push({ id: v.id, label: v.label, mobility: v.mobility, required_views: ["side"] }); await api("PUT", "/api/classes", { classes }); await reloadCatalog(); render(); }) }), state),
    h("div", { class: "panel" }, body, errBox));
  render();
}

// ---------------------------------------------------------------- agent jobs
async function jobsScreen() {
  const box = h("div");
  const render = async () => {
    const list = (await api("GET", "/api/jobs")).jobs;
    box.textContent = "";
    if (!list.length) { box.append(h("p", { class: "muted", text: "No jobs since the tool was started. Start one from a unit screen (AI panel)." })); return; }
    box.append(h("table", {},
      h("thead", {}, h("tr", {}, ["Job", "Kind", "Unit", "State", "Started", "Duration", "Cost"].map((t) => h("th", { text: t })))),
      h("tbody", {}, list.map((j) => h("tr", { class: "clickable", onclick: () => { location.hash = "#/job/" + encodeURIComponent(j.id); } },
        h("td", { class: "mono", text: j.id }), h("td", { text: j.kind + (j.faction ? " (" + j.faction + ")" : "") }),
        h("td", { class: "mono", text: j.unit_id }), h("td", {}, jobBadge(j.state)),
        h("td", { class: "mono", text: fmtTime(j.started) }), h("td", { class: "mono", text: fmtDuration(j) }),
        h("td", { class: "num", text: j.cost_usd ? "$" + j.cost_usd.toFixed(2) : "" }))))));
  };
  app.append(h("div", { class: "panel" }, h("h1", { text: "Agent jobs" }),
    ai.available ? h("p", { class: "muted", text: "Claude Code: " + ai.claude + " - one job runs at a time, the rest wait in the queue. Jobs are kept in memory until the tool is restarted." })
      : h("p", { class: "errors", text: ai.hint }), box));
  await render();
  const timer = setInterval(() => render().catch(() => {}), 3000);
  cleanup = () => clearInterval(timer);
}

async function jobScreen(jobId) {
  let job = await api("GET", "/api/jobs/" + encodeURIComponent(jobId));
  const log = h("div", { class: "joblog" });
  const head = h("div", { class: "row" });
  const tail = h("div");
  let next = 0;
  const appendLog = (entries) => {
    const stick = log.scrollTop + log.clientHeight >= log.scrollHeight - 30;
    for (const e of entries) {
      log.append(h("div", { class: "le le-" + e.kind + (e.sub ? " le-sub" : "") },
        h("span", { class: "le-t", text: new Date(e.t * 1000).toLocaleTimeString() }), " ",
        e.kind === "tool" ? "→ " : e.kind === "error" ? "✗ " : "", e.text));
    }
    if (stick) log.scrollTop = log.scrollHeight;
  };
  const renderHead = () => {
    head.textContent = "";
    head.append(h("h1", { style: "margin:0;flex:1", text: job.kind + " · " + job.unit_id }), jobBadge(job.state),
      h("span", { class: "mono muted", text: fmtDuration(job) }),
      h("a", { class: "btn", href: "#/unit/" + encodeURIComponent(job.unit_id), text: "Open unit" }),
      ACTIVE_JOB.includes(job.state) ? h("button", { class: "danger", text: "Stop", onclick: async () => { job = await api("POST", "/api/jobs/" + encodeURIComponent(jobId) + "/cancel", {}); renderHead(); } }) : null);
  };
  const renderTail = () => {
    tail.textContent = "";
    if (ACTIVE_JOB.includes(job.state)) return;
    if (job.error) tail.append(h("div", { class: "errors", text: job.error }));
    if (job.result) tail.append(h("h3", { text: "Agent summary" }), h("pre", { class: "jobresult", text: job.result }));
    if (job.report) {
      const r = job.report;
      tail.append(h("h3", { text: "Merged into the unit" }), h("p", { text: "Filled " + r.filled.length + ", suggested " + r.suggested.length + ", image candidates " + r.candidates + ". Verify them on the unit screen." }),
        r.rejected.length ? h("div", { class: "errors", text: "Rejected:\n" + r.rejected.map((x) => x.field + ": " + x.message).join("\n") }) : null);
    }
    if (job.changed_files && job.changed_files.length) tail.append(h("h3", { text: "Changed files (git status) - not committed" }), h("pre", { class: "jobresult", text: job.changed_files.join("\n") }));
    if (job.session_id) tail.append(h("p", { class: "muted" }, "Continue in a terminal: ", h("code", { class: "mono", text: "claude --resume " + job.session_id })));
    if (job.cost_usd) tail.append(h("p", { class: "muted", text: "Cost: $" + job.cost_usd.toFixed(2) }));
  };
  const update = (data) => { job = data; appendLog(data.log); next = data.log_from + data.log.length; renderHead(); renderTail(); };
  app.append(h("div", { class: "editor-head" }, h("a", { href: "#/jobs", text: "< Jobs" })),
    h("div", { class: "panel" }, head, h("p", { class: "mono muted", text: job.id }), log, tail));
  update(job);
  const timer = setInterval(async () => {
    if (!ACTIVE_JOB.includes(job.state)) { clearInterval(timer); return; }
    try { update(await api("GET", "/api/jobs/" + encodeURIComponent(jobId) + "?since=" + next)); } catch (e) { /* keep polling */ }
  }, 1500);
  cleanup = () => clearInterval(timer);
}

// ---------------------------------------------------------------- unit editor
const NUM_FIELDS = ["weight_t", "speed_road_kmh", "speed_offroad_kmh", "range_km", "fire_range_km"];
const DIM_FIELDS = ["hull_length", "overall_length", "width", "height"];
// Unverified AI values in these fields block ready_for_model (mirrors catalog.MODEL_CRITICAL_FIELDS).
const MODEL_CRITICAL = ["dimensions.hull_length", "dimensions.width", "dimensions.height", "silhouette_features"];
const researchReports = {}; // unit id -> report of the last "Apply research", shown once after the reload

function getPath(obj, path) { return path.split(".").reduce((o, k) => (o && typeof o === "object" ? o[k] : undefined), obj); }
function setPath(obj, path, value) {
  const keys = path.split(".");
  const last = keys.pop();
  for (const k of keys) obj = obj[k] = obj[k] || {};
  obj[last] = value;
}
// Wikimedia originals can be 20+ MB: show a 330 px thumbnail (a standard size - others get HTTP 400): .../thumb/a/ab/F.jpg/330px-F.jpg.
function thumbUrl(url) {
  const m = /^(https:\/\/upload\.wikimedia\.org\/wikipedia\/[^/]+)\/([0-9a-f]\/[0-9a-f]{2})\/([^/]+\.(?:jpe?g|png|webp))$/i.exec(url);
  return m ? m[1] + "/thumb/" + m[2] + "/" + m[3] + "/330px-" + m[3] : url;
}
function showValue(v) { return Array.isArray(v) ? v.join("; ") : String(v); }

function readiness(u) {
  const dims = u.dimensions || {};
  const pos = (v) => typeof v === "number" && v > 0;
  const feats = (u.silhouette_features || []).filter((s) => s.trim());
  return [
    ["Real name", !!(u.real_name || "").trim()],
    ["Class", !!u.class],
    ["At least one operator", (u.operators || []).length >= 1],
    ["Height", pos(dims.height)],
    ["Width", pos(dims.width)],
    ["Hull length", pos(dims.hull_length)],
    ["At least 3 silhouette features (" + feats.length + ")", feats.length >= 3],
    ["A side or drawing image", (u.images || []).some((i) => i.view === "side" || i.view === "drawing")],
  ].concat(MODEL_CRITICAL.filter((p) => ((u.provenance || {})[p] || {}).verified === false).map((p) => ["Verify " + pretty(p.replace("dimensions.", "")) + " (AI value)", false]));
}

async function unitScreen(id) {
  let detail = await api("GET", "/api/units/" + encodeURIComponent(id));
  const u = detail.unit;
  u.dimensions = u.dimensions || {};
  u.armament = u.armament || {};
  for (const k of ["operators", "silhouette_features", "details", "skip", "images", "image_candidates"]) u[k] = u[k] || [];
  u.provenance = u.provenance || {};
  u.dimensions.sources = u.dimensions.sources || [];
  let serverStatus = u.status;
  let review = detail.review;
  const bust = Date.now();

  const state = h("span", { class: "savestate saved", text: "saved" });
  const errBox = h("div", { class: "errors" });
  const checkBox = h("ul", { class: "check" });
  const statusSel = h("select");
  const reviewBox = h("div");
  const imagesBox = h("div");
  const featBox = h("div");
  // All server writes of this screen go through one promise chain, so an older request never lands after a newer one.
  let chain = Promise.resolve();
  const enqueue = (fn) => { const p = chain.then(fn); chain = p.catch(() => {}); return p; };
  const onConflict = () => {
    errBox.textContent = "This unit was changed elsewhere (another tab or an agent). Your last edits were not saved; reloading the latest version...";
    state.className = "savestate error"; state.textContent = "conflict";
    window.__pendingSave = null;
    setTimeout(route, 2500);
  };
  const doSave = () => enqueue(async () => {
    state.className = "savestate saving"; state.textContent = "saving...";
    try {
      const res = await api("PUT", "/api/units/" + encodeURIComponent(id), u);
      u.revision = res.unit.revision;
      review = res.review;
      serverStatus = u.status; errBox.textContent = "";
      state.className = "savestate saved"; state.textContent = "saved";
    } catch (e) {
      if (e.status === 409) { onConflict(); return; }
      state.className = "savestate error"; state.textContent = "not saved";
      errBox.textContent = errText(e);
      if (u.status !== serverStatus && (e.errors || []).some((x) => x.field === "status")) { u.status = serverStatus; renderStatus(); }
    }
  });
  const save = debounce(doSave, 700);
  window.__pendingSave = save.pending;
  // While an agent job works on this unit the form is read-only; the screen reloads when the job ends.
  const activeJob = detail.job;
  let jobTimer = null;
  if (activeJob) {
    jobTimer = setInterval(async () => {
      try {
        const j = await api("GET", "/api/jobs/" + encodeURIComponent(activeJob.id) + "?since=999999999");
        if (!ACTIVE_JOB.includes(j.state)) { clearInterval(jobTimer); route(); }
      } catch (e) { /* keep polling */ }
    }, 2000);
  }
  cleanup = async () => { if (jobTimer) clearInterval(jobTimer); window.__pendingSave = null; save.flush(); window.removeEventListener("paste", onPaste); await chain; };
  const changed = () => { state.className = "savestate saving"; state.textContent = "editing..."; renderChecklist(); save(); };

  function renderChecklist() {
    const items = readiness(u);
    checkBox.textContent = "";
    for (const [t, ok] of items) checkBox.append(h("li", { class: ok ? "ok" : "", text: t }));
    const ready = items.every((x) => x[1]);
    for (const opt of statusSel.options) if (opt.value === "ready_for_model") opt.disabled = !ready && u.status !== "ready_for_model";
    return ready;
  }
  function renderStatus() {
    statusSel.textContent = "";
    for (const s of catalog.statuses) statusSel.append(h("option", { value: s, text: s, selected: u.status === s }));
    renderChecklist();
  }
  statusSel.addEventListener("change", () => { u.status = statusSel.value; changed(); });

  // ---- field builders
  // `path` (dotted, e.g. "dimensions.height") marks a field AI research may fill: it shows where the value came
  // from, whether the human verified it, and a different value the AI found for a field the human had filled.
  const field = (lbl, control, wide, path) => {
    const wrap = h("div", { class: "field" + (wide ? " wide" : "") }, h("label", { text: lbl }), control);
    if (!path) return wrap;
    const box = h("div", { class: "prov" });
    wrap.append(box);
    const render = () => {
      const p = u.provenance[path];
      box.textContent = "";
      wrap.classList.toggle("ai-unverified", !!p && p.verified === false);
      if (!p) return;
      const src = p.source ? h("a", { href: p.source, target: "_blank", rel: "noopener noreferrer", text: "source" }) : h("span", { text: "no source" });
      if (p.verified === false) {
        box.append(h("span", { class: "ai-tag", text: "AI" }), " unverified · ", src, " ",
          h("button", { class: "small", text: "✓ Verified", title: "I checked this value", onclick: () => { p.verified = true; render(); changed(); } }));
      } else if (p.suggested === undefined) {
        box.append(h("span", { class: "muted", text: "AI · verified · " }), src);
      }
      if (p.suggested !== undefined) {
        box.append(h("div", { class: "suggest" }, h("span", { class: "ai-tag", text: "AI" }), " suggests: ", h("strong", { text: showValue(p.suggested) }), " · ", src, " ",
          h("button", { class: "small", text: "Use", onclick: () => useSuggestion(path) }),
          h("button", { class: "small", text: "Dismiss", onclick: () => { delete p.suggested; render(); changed(); } })));
      }
    };
    // editing the value by hand counts as verifying it
    const touched = () => { const p = u.provenance[path]; if (p && p.verified === false) { p.verified = true; render(); renderChecklist(); } };
    wrap.addEventListener("input", touched);
    wrap.addEventListener("change", touched);
    render();
    return wrap;
  };
  async function useSuggestion(path) {
    const p = u.provenance[path];
    setPath(u, path, p.suggested);
    delete p.suggested;
    p.verified = true;
    save.flush();
    await doSave();
    route(); // rebuild the controls with the new value
  }
  const textIn = (obj, key, ph) => h("input", { type: "text", value: obj[key] === undefined ? "" : obj[key], placeholder: ph || "", oninput: (e) => { obj[key] = e.target.value; changed(); } });
  const numIn = (obj, key, ph) => {
    const input = h("input", { type: "text", inputmode: "decimal", value: obj[key] === undefined ? "" : obj[key], placeholder: ph || "" });
    input.addEventListener("input", () => {
      const raw = input.value.trim().replace(",", ".");
      if (raw === "") { delete obj[key]; input.classList.remove("invalid"); }
      else if (isFinite(Number(raw))) { obj[key] = Number(raw); input.classList.remove("invalid"); }
      else { obj[key] = raw; input.classList.add("invalid"); }
      changed();
    });
    return input;
  };
  const areaIn = (obj, key, ph, rows) => h("textarea", { placeholder: ph || "", rows: rows || 3, oninput: (e) => { obj[key] = e.target.value; changed(); } }, obj[key] || "");
  const linesIn = (obj, key, ph) => h("textarea", { placeholder: ph, rows: 4, oninput: (e) => { obj[key] = e.target.value.split("\n").filter((l) => l.trim()); changed(); } }, (obj[key] || []).join("\n"));

  const classSel = h("select", { onchange: (e) => {
    u.class = e.target.value;
    const c = catalog.classes.find((x) => x.id === u.class);
    if (c) { u.mobility = c.mobility; mobSel.value = c.mobility; }
    changed();
  } }, catalog.classes.map((c) => h("option", { value: c.id, text: c.label, selected: u.class === c.id })));
  const mobSel = h("select", { onchange: (e) => { u.mobility = e.target.value; changed(); } }, catalog.mobilities.map((m) => h("option", { value: m, text: m, selected: u.mobility === m })));

  const operators = h("div", { class: "multi" }, catalog.factions.map((f) => {
    const cb = h("input", { type: "checkbox", checked: u.operators.includes(f.id) });
    const lab = h("label", { class: cb.checked ? "on" : "" }, cb, h("i", { class: "dot", style: "background:" + f.color }), f.name);
    cb.addEventListener("change", () => {
      const s = new Set(u.operators);
      if (cb.checked) s.add(f.id); else s.delete(f.id);
      u.operators = catalog.factions.map((x) => x.id).filter((x) => s.has(x));
      lab.classList.toggle("on", cb.checked); changed();
    });
    return lab;
  }));

  function renderFeatures() {
    featBox.textContent = "";
    const list = u.silhouette_features;
    const move = (i, d) => { const j = i + d; if (j < 0 || j >= list.length) return; [list[i], list[j]] = [list[j], list[i]]; renderFeatures(); changed(); };
    list.forEach((txt, i) => featBox.append(h("div", { class: "feat" },
      h("span", { class: "idx", text: i + 1 }),
      h("input", { type: "text", value: txt, oninput: (e) => { list[i] = e.target.value; changed(); } }),
      h("button", { class: "small", title: "Move up", text: "↑", disabled: i === 0, onclick: () => move(i, -1) }),
      h("button", { class: "small", title: "Move down", text: "↓", disabled: i === list.length - 1, onclick: () => move(i, 1) }),
      h("button", { class: "small danger", title: "Remove", text: "×", onclick: () => { list.splice(i, 1); renderFeatures(); changed(); } }))));
    const add = h("input", { type: "text", placeholder: "Add a feature and press Enter (most recognisable first)..." });
    add.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && add.value.trim()) { list.push(add.value.trim()); renderFeatures(); changed(); featBox.lastChild.focus(); }
    });
    featBox.append(add);
  }

  // ---- images
  let uploadView = "side";
  const viewSel = h("select", { style: "width:auto", onchange: (e) => { uploadView = e.target.value; } }, catalog.views.map((v) => h("option", { value: v, text: pretty(v), selected: v === uploadView })));
  const fileInput = h("input", { type: "file", accept: "image/png,image/jpeg,image/webp", multiple: true, hidden: true });
  fileInput.addEventListener("change", () => { uploadFiles(Array.from(fileInput.files)); fileInput.value = ""; });
  const dropzone = h("div", { class: "dropzone" },
    "Drop images here, press Ctrl+V to paste a copied image, or ",
    h("button", { class: "small", text: "choose files", onclick: () => fileInput.click() }),
    h("div", { class: "row", style: "justify-content:center;margin-top:8px" }, h("span", { text: "Add as view:" }), viewSel), fileInput);
  dropzone.addEventListener("dragover", (e) => { e.preventDefault(); dropzone.classList.add("over"); });
  dropzone.addEventListener("dragleave", () => dropzone.classList.remove("over"));
  dropzone.addEventListener("drop", (e) => { e.preventDefault(); dropzone.classList.remove("over"); uploadFiles(Array.from(e.dataTransfer.files)); });
  function onPaste(e) {
    const items = (e.clipboardData && e.clipboardData.items) || [];
    const files = [];
    for (const it of items) if (it.kind === "file" && it.type.startsWith("image/")) files.push(it.getAsFile());
    if (files.length) { e.preventDefault(); uploadFiles(files); }
  }
  window.addEventListener("paste", onPaste);

  function readB64(file) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result).split(",", 2)[1]);
      r.onerror = () => reject(new Error("cannot read file"));
      r.readAsDataURL(file);
    });
  }
  async function uploadFiles(files) {
    if (activeJob) return; // read-only while an agent job runs
    for (const file of files) {
      if (file.size > 15 * 1024 * 1024) { errBox.textContent = file.name + ": larger than 15 MB"; continue; }
      state.className = "savestate saving"; state.textContent = "uploading...";
      try {
        const data = await readB64(file);
        const view = uploadView;
        save.flush(); // pending edits are queued first, so the upload sees the latest revision
        await enqueue(async () => {
          const res = await api("POST", "/api/units/" + encodeURIComponent(id) + "/images", { view, data });
          u.images.push(res.image);
          u.revision = res.unit.revision;
          review = res.review;
        });
        errBox.textContent = ""; state.className = "savestate saved"; state.textContent = "saved";
        renderImages(); renderChecklist(); renderReview();
      } catch (e) {
        if (e.status === 409) { onConflict(); return; }
        state.className = "savestate error"; state.textContent = "upload failed"; errBox.textContent = errText(e);
      }
    }
  }
  const candBox = h("div");
  function renderCandidates() {
    candBox.textContent = "";
    if (!u.image_candidates.length) return;
    candBox.append(h("h3", { text: "AI image candidates (" + u.image_candidates.length + ") - check the licence and the view, then download" }),
      h("div", { class: "cards", style: "margin-bottom:14px" }, u.image_candidates.map((c) => {
        const img = h("img", { src: thumbUrl(c.url), alt: c.url.split("/").pop(), loading: "lazy", referrerpolicy: "no-referrer", onclick: () => showLightbox(c.url) });
        img.addEventListener("error", () => { if (img.src !== c.url) img.src = c.url; else img.replaceWith(h("div", { class: "thumb-missing", text: "preview unavailable" })); });
        return h("div", { class: "card candidate" }, img,
          h("div", { class: "fname" }, h("span", { class: "badge", text: pretty(c.view) }),
            h("a", { href: c.source_page || c.url, target: "_blank", rel: "noopener noreferrer", text: c.source_page ? "file page" : "open" })),
          h("div", { style: "font-size:13px" }, c.license || h("span", { class: "bad", text: "licence unknown" })),
          c.note ? h("div", { class: "muted", style: "font-size:12.5px", text: c.note }) : null,
          h("div", { class: "row" },
            h("button", { class: "small primary", text: "Download", onclick: () => candidateAction(c, "download") }),
            h("button", { class: "small danger", text: "Dismiss", onclick: () => candidateAction(c, "dismiss") })));
      })));
  }
  async function candidateAction(c, action) {
    state.className = "savestate saving"; state.textContent = action === "download" ? "downloading..." : "saving...";
    try {
      save.flush();
      await enqueue(async () => {
        const res = await api("POST", "/api/units/" + encodeURIComponent(id) + "/candidates", { action, url: c.url });
        if (res.image) u.images.push(res.image);
        u.image_candidates = res.unit.image_candidates || [];
        u.revision = res.unit.revision;
        review = res.review;
      });
      errBox.textContent = ""; state.className = "savestate saved"; state.textContent = "saved";
      renderCandidates(); renderImages(); renderChecklist(); renderReview();
    } catch (e) {
      if (e.status === 409) { onConflict(); return; }
      state.className = "savestate error"; state.textContent = "not saved"; errBox.textContent = errText(e);
    }
  }

  async function restoreImages() {
    try {
      save.flush();
      await chain;
      const res = await api("POST", "/api/units/" + encodeURIComponent(id) + "/images/restore", {});
      if (res.report.failed.length) alert("Not restored:\n" + res.report.failed.map((f) => f.file + ": " + f.message).join("\n"));
      route();
    } catch (e) { errBox.textContent = errText(e); }
  }

  function renderImages() {
    imagesBox.textContent = "";
    if (detail.missing_images.length) {
      imagesBox.append(h("div", { class: "row", style: "margin-bottom:10px" },
        h("span", { class: "bad", text: detail.missing_images.length + " image file(s) missing on this computer." }),
        h("button", { class: "small", text: "Restore from source URLs", onclick: restoreImages })));
    }
    if (!u.images.length) { imagesBox.append(h("p", { class: "muted", text: "No images yet." })); return; }
    for (const view of catalog.views) {
      const group = u.images.filter((i) => i.view === view);
      if (!group.length) continue;
      imagesBox.append(h("h3", { text: pretty(view) + " (" + group.length + ")" }), h("div", { class: "cards", style: "margin-bottom:14px" }, group.map((img) => {
        const src = fileUrl(id, img.file, bust);
        const missing = detail.missing_images.includes(img.file);
        const localOnly = !/^https:\/\//.test(img.source_url || "");
        return h("div", { class: "card" },
          missing ? h("div", { class: "thumb-missing", text: "not on this computer" + (localOnly ? " (no source URL to restore from)" : " - use Restore") })
            : h("img", { src, alt: img.file, onclick: () => showLightbox(src) }),
          localOnly && !missing ? h("div", { class: "warn-note", text: "Only on this computer (images are not in git). Add the https source URL so it can be restored elsewhere." }) : null,
          h("div", { class: "fname" }, img.file, h("button", { class: "small danger", text: "delete", onclick: () => deleteImage(img) })),
          h("select", { onchange: (e) => { img.view = e.target.value; renderImages(); changed(); } }, catalog.views.map((v) => h("option", { value: v, text: pretty(v), selected: img.view === v }))),
          h("input", { type: "text", placeholder: "Source URL", value: img.source_url || "", oninput: (e) => { img.source_url = e.target.value; changed(); } }),
          h("input", { type: "text", placeholder: "Licence", value: img.license || "", oninput: (e) => { img.license = e.target.value; changed(); } }),
          h("input", { type: "text", placeholder: "Note", value: img.note || "", oninput: (e) => { img.note = e.target.value; changed(); } }));
      })));
    }
  }
  async function deleteImage(img) {
    if (!confirm("Delete " + img.file + "?")) return;
    try {
      save.flush();
      await enqueue(async () => {
        const res = await api("DELETE", "/api/units/" + encodeURIComponent(id) + "/images/" + encodeURIComponent(img.file));
        u.images = u.images.filter((i) => i.file !== img.file);
        u.revision = res.unit.revision;
        review = res.review;
      });
      errBox.textContent = "";
      renderImages(); renderChecklist(); renderReview();
    } catch (e) { errBox.textContent = errText(e); }
  }

  // ---- model review
  function renderReview() {
    reviewBox.textContent = "";
    if (!review || (!review.blueprint && !review.sheet)) return;
    const ref = u.images.find((i) => i.view === "side") || u.images.find((i) => i.view === "drawing");
    reviewBox.append(h("div", { class: "panel" }, h("h2", { text: "Model review" }),
      h("div", { class: "review" },
        review.sheet ? h("div", {}, h("h3", { text: "Latest render sheet" }), h("img", { src: "/files/screenshots/" + encodeURIComponent(review.sheet) + "?v=" + Date.now(), onclick: () => showLightbox("/files/screenshots/" + encodeURIComponent(review.sheet) + "?v=" + Date.now()) })) : null,
        ref ? h("div", {}, h("h3", { text: "Side reference" }), h("img", { src: fileUrl(id, ref.file, bust), onclick: () => showLightbox(fileUrl(id, ref.file, bust)) })) : null,
        review.blueprint ? h("div", {}, h("h3", { text: "blueprint.md (read-only)" }), h("pre", { text: review.blueprint })) : null),
      h("p", { class: "muted", text: "Write your remarks in the Feedback box below; the modeler reads them on the next /model-unit run." })));
  }

  // ---- layout
  const section = (title, ...children) => h("div", { class: "panel" }, h("h2", { text: title }), children);
  const mainCol = h("div", {},
    section("Identity", h("div", { class: "grid" },
      field("Real name (shown in game)", textIn(u, "real_name", "Leopard 2A4")),
      field("Variant note", textIn(u, "variant_note"), false, "variant_note"),
      field("Class", classSel), field("Mobility", mobSel),
      field("In service (years)", textIn(u, "in_service", "1985-present"), false, "in_service"),
      field("Country of origin", textIn(u, "country_of_origin"), false, "country_of_origin"),
      field("Operators (factions)", operators, true, "operators"))),
    section("Real-world facts", h("div", { class: "grid" },
      field("Crew", textIn(u, "crew", "4"), false, "crew"), field("Weight (t)", numIn(u, "weight_t"), false, "weight_t"),
      field("Speed road (km/h)", numIn(u, "speed_road_kmh"), false, "speed_road_kmh"), field("Speed off-road (km/h)", numIn(u, "speed_offroad_kmh"), false, "speed_offroad_kmh"),
      field("Range (km)", numIn(u, "range_km"), false, "range_km"), field("Fire range (km, artillery)", numIn(u, "fire_range_km"), false, "fire_range_km"),
      field("Main armament", textIn(u.armament, "main"), false, "armament.main"), field("Secondary armament", textIn(u.armament, "secondary"), false, "armament.secondary"),
      field("Protection", areaIn(u, "protection", "", 2), true, "protection"), field("Notes", areaIn(u, "notes", "", 3), true, "notes"))),
    section("Dimensions (metres)", h("div", { class: "grid" },
      field("Hull length *", numIn(u.dimensions, "hull_length"), false, "dimensions.hull_length"), field("Overall length (with gun)", numIn(u.dimensions, "overall_length"), false, "dimensions.overall_length"),
      field("Width *", numIn(u.dimensions, "width"), false, "dimensions.width"), field("Height *", numIn(u.dimensions, "height"), false, "dimensions.height"),
      field("Sources (one URL per line)", linesIn(u.dimensions, "sources", "https://..."), true))),
    section("For the modeler",
      field("Silhouette features (most recognisable first)", featBox, false, "silhouette_features"),
      h("div", { class: "grid two", style: "margin-top:10px" },
        field("Details (nice to have, one per line)", linesIn(u, "details", ""), false, "details"),
        field("Skip (leave out, one per line)", linesIn(u, "skip", ""), false, "skip"),
        field("Camo note", areaIn(u, "camo_note", "How the real vehicle is painted / what to do with faction camo", 3), true, "camo_note"))),
    section("Images", candBox, dropzone, imagesBox),
    reviewBox,
    section("Status & feedback", h("div", { class: "grid two" },
      field("Status", statusSel),
      field("Feedback for the modeler (on the latest render)", areaIn(u, "feedback", "e.g. turret too tall, barrel too thin...", 4), true))));
  const side = h("div", { class: "side" }, h("div", { class: "panel" }, h("h2", { text: "Ready for model?" }), checkBox,
    h("p", { class: "muted", style: "font-size:13px", text: "The status can only be set to ready_for_model when everything is checked. Going back is always allowed." })),
    researchPanel());

  function researchPanel() {
    const box = h("div", { class: "panel" }, h("h2", { text: "AI" }));
    const unverified = Object.keys(u.provenance).filter((p) => u.provenance[p].verified === false);
    const suggested = Object.keys(u.provenance).filter((p) => u.provenance[p].suggested !== undefined);
    if (activeJob) {
      box.append(h("p", {}, jobBadge(activeJob.state), " ", activeJob.kind + " job - the form is read-only until it ends. ",
        h("a", { href: "#/job/" + encodeURIComponent(activeJob.id), text: "Live log" })));
    } else if (detail.pending_research) {
      box.append(h("p", { text: "A research result (research.json) is waiting to be merged." }),
        h("button", { class: "primary", text: "Apply research", onclick: applyResearch }));
    } else if (ai.available) {
      box.append(h("button", { class: "primary", text: "Research with AI", onclick: () => runJob("research") }),
        h("p", { class: "muted", style: "font-size:13px" }, "Searches the web and fills empty fields; values are marked ", h("span", { class: "ai-tag", text: "AI" }), " until you verify them."));
    } else {
      box.append(h("p", { class: "muted", style: "font-size:13px" }, ai.hint, " Meanwhile: run ", h("code", { class: "mono", text: "/research-unit " + id }), " in Claude Code, the result appears here to apply."));
    }
    if (ai.available && !activeJob && (u.status === "ready_for_model" || u.status === "modeled")) {
      const facs = u.operators.concat(catalog.factions.map((f) => f.id).filter((f) => !u.operators.includes(f)));
      const facSel = h("select", { style: "width:auto" }, facs.map((f) => h("option", { value: f, text: label(catalog.factions, f, "name") })));
      box.append(h("div", { class: "row", style: "margin-top:10px" },
        h("button", { text: u.status === "modeled" ? "Rework model" : "Build model", onclick: () => runJob("model", facSel.value) }),
        h("span", { class: "muted", text: "render as" }), facSel),
        h("p", { class: "muted", style: "font-size:13px", text: u.status === "modeled" ? "Uses your Feedback below as the main input. Takes several minutes; changes are not committed." : "Runs /model-unit. Takes several minutes; changes are not committed." }));
    }
    if (unverified.length || suggested.length) {
      box.append(h("p", { style: "font-size:13px" }, h("strong", { text: unverified.length + " unverified" }), ", " + suggested.length + " suggestion(s)"));
    }
    const report = researchReports[id];
    if (report) {
      delete researchReports[id];
      box.append(h("div", { class: "report" },
        h("div", { text: "Filled " + report.filled.length + ", suggested " + report.suggested.length + ", image candidates " + report.candidates + "." }),
        report.rejected.length ? h("div", { class: "errors", text: "Rejected:\n" + report.rejected.map((r) => r.field + ": " + r.message).join("\n") }) : null,
        report.summary ? h("pre", { text: report.summary }) : null));
    }
    return box;
  }
  async function runJob(kind, faction) {
    try {
      save.flush();
      await chain;
      await startJob(kind, id, faction);
      route();
    } catch (e) { errBox.textContent = errText(e); }
  }
  async function applyResearch() {
    try {
      save.flush();
      await chain;
      const res = await api("POST", "/api/units/" + encodeURIComponent(id) + "/research/apply");
      researchReports[id] = res.report;
      route();
    } catch (e) { errBox.textContent = errText(e); }
  }
  app.append(
    h("div", { class: "editor-head" }, h("a", { href: "#/", text: "< Overview" }), h("h1", { text: u.real_name }), h("span", { class: "mono muted", text: id }),
      h("a", { class: "btn", href: "/files/units/" + encodeURIComponent(id) + "/unit.json", target: "_blank", text: "unit.json" }), state),
    errBox, h("div", { class: "layout" }, h("fieldset", { class: "lock", disabled: !!activeJob }, mainCol), side));
  renderStatus(); renderFeatures(); renderCandidates(); renderImages(); renderReview();
}

route();
