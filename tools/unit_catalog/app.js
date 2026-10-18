"use strict";
// Unit catalog UI (TASK-037). Vanilla JS, no build step, no network except the local API.

const app = document.getElementById("app");
let catalog = { classes: [], factions: [], units: [], views: [], statuses: [], mobilities: [] };
let cleanup = null; // called when leaving a screen
const filters = { faction: "", cls: "", status: "", q: "" };

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
    const input = f.options
      ? h("select", {}, f.options.map((o) => h("option", { value: o.value, text: o.label })))
      : h("input", { type: "text", value: f.value || "", placeholder: f.placeholder || "" });
    inputs[f.key] = input;
    if (f.onInput) input.addEventListener("input", () => f.onInput(input, inputs));
    return h("div", { class: "field" }, h("label", { text: f.label }), input);
  });
  const submit = async () => {
    const values = {};
    for (const k of Object.keys(inputs)) values[k] = inputs[k].value;
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
}

// ---------------------------------------------------------------- routing
async function route() {
  if (cleanup) { try { await cleanup(); } catch (e) { /* ignore */ } cleanup = null; }
  const parts = location.hash.replace(/^#\/?/, "").split("/").map(decodeURIComponent);
  document.querySelectorAll("[data-nav]").forEach((a) => a.classList.toggle("active", a.dataset.nav === (parts[0] === "classes" ? "classes" : "overview")));
  app.textContent = "";
  try {
    await reloadCatalog();
    if (parts[0] === "unit" && parts[1]) await unitScreen(parts[1]);
    else if (parts[0] === "faction" && parts[1]) factionScreen(parts[1]);
    else if (parts[0] === "classes") classesScreen();
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
        h("button", { class: "primary", text: "New unit", onclick: newUnitDialog })),
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
  ], async (v) => {
    const body = { real_name: v.real_name, id: v.id, class: v.class, operators: v.operator ? [v.operator] : [] };
    const created = await api("POST", "/api/units", body);
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

// ---------------------------------------------------------------- unit editor
const NUM_FIELDS = ["weight_t", "speed_road_kmh", "speed_offroad_kmh", "range_km", "fire_range_km"];
const DIM_FIELDS = ["hull_length", "overall_length", "width", "height"];

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
  ];
}

async function unitScreen(id) {
  let detail = await api("GET", "/api/units/" + encodeURIComponent(id));
  const u = detail.unit;
  u.dimensions = u.dimensions || {};
  u.armament = u.armament || {};
  for (const k of ["operators", "silhouette_features", "details", "skip", "images"]) u[k] = u[k] || [];
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
  cleanup = async () => { window.__pendingSave = null; save.flush(); window.removeEventListener("paste", onPaste); await chain; };
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
  const field = (lbl, control, wide) => h("div", { class: "field" + (wide ? " wide" : "") }, h("label", { text: lbl }), control);
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
  function renderImages() {
    imagesBox.textContent = "";
    if (!u.images.length) { imagesBox.append(h("p", { class: "muted", text: "No images yet." })); return; }
    for (const view of catalog.views) {
      const group = u.images.filter((i) => i.view === view);
      if (!group.length) continue;
      imagesBox.append(h("h3", { text: pretty(view) + " (" + group.length + ")" }), h("div", { class: "cards", style: "margin-bottom:14px" }, group.map((img) => {
        const src = fileUrl(id, img.file, bust);
        return h("div", { class: "card" },
          h("img", { src, alt: img.file, onclick: () => showLightbox(src) }),
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
      field("Variant note", textIn(u, "variant_note")),
      field("Class", classSel), field("Mobility", mobSel),
      field("In service (years)", textIn(u, "in_service", "1985-present")),
      field("Country of origin", textIn(u, "country_of_origin")),
      h("div", { class: "field wide" }, h("label", { text: "Operators (factions)" }), operators))),
    section("Real-world facts", h("div", { class: "grid" },
      field("Crew", textIn(u, "crew", "4")), field("Weight (t)", numIn(u, "weight_t")),
      field("Speed road (km/h)", numIn(u, "speed_road_kmh")), field("Speed off-road (km/h)", numIn(u, "speed_offroad_kmh")),
      field("Range (km)", numIn(u, "range_km")), field("Fire range (km, artillery)", numIn(u, "fire_range_km")),
      field("Main armament", textIn(u.armament, "main")), field("Secondary armament", textIn(u.armament, "secondary")),
      field("Protection", areaIn(u, "protection", "", 2), true), field("Notes", areaIn(u, "notes", "", 3), true))),
    section("Dimensions (metres)", h("div", { class: "grid" },
      field("Hull length *", numIn(u.dimensions, "hull_length")), field("Overall length (with gun)", numIn(u.dimensions, "overall_length")),
      field("Width *", numIn(u.dimensions, "width")), field("Height *", numIn(u.dimensions, "height")),
      field("Sources (one URL per line)", linesIn(u.dimensions, "sources", "https://..."), true))),
    section("For the modeler",
      h("div", { class: "field" }, h("label", { text: "Silhouette features (most recognisable first)" }), featBox),
      h("div", { class: "grid two", style: "margin-top:10px" },
        field("Details (nice to have, one per line)", linesIn(u, "details", "")),
        field("Skip (leave out, one per line)", linesIn(u, "skip", "")),
        field("Camo note", areaIn(u, "camo_note", "How the real vehicle is painted / what to do with faction camo", 3), true))),
    section("Images", dropzone, imagesBox),
    reviewBox,
    section("Status & feedback", h("div", { class: "grid two" },
      field("Status", statusSel),
      field("Feedback for the modeler (on the latest render)", areaIn(u, "feedback", "e.g. turret too tall, barrel too thin...", 4), true))));
  const side = h("div", { class: "side" }, h("div", { class: "panel" }, h("h2", { text: "Ready for model?" }), checkBox,
    h("p", { class: "muted", style: "font-size:13px", text: "The status can only be set to ready_for_model when everything is checked. Going back is always allowed." })));
  app.append(
    h("div", { class: "editor-head" }, h("a", { href: "#/", text: "< Overview" }), h("h1", { text: u.real_name }), h("span", { class: "mono muted", text: id }),
      h("a", { class: "btn", href: "/files/units/" + encodeURIComponent(id) + "/unit.json", target: "_blank", text: "unit.json" }), state),
    errBox, h("div", { class: "layout" }, mainCol, side));
  renderStatus(); renderFeatures(); renderImages(); renderReview();
}

route();
