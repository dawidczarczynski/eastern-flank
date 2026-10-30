"use strict";
// Backlog viewer: docs/tasks/BACKLOG.md as a table or a board, with sorting, filters and a task file panel.
// Polls /api/version every second and re-renders when a file changed.

const STORE = "backlog_view.state.v2";
const POLL_MS = 1000;
const OPEN = ["in progress", "to playtest", "ready", "blocked", "idea"];
const state = Object.assign(
  { sort: "order", desc: false, statuses: OPEN.slice(), query: "", model: "", view: "table" },
  JSON.parse(localStorage.getItem(STORE) || "{}")
);
const urlView = new URLSearchParams(location.search).get("view"); // ?view=board / ?view=table
if (urlView === "board" || urlView === "table") state.view = urlView;
let data = null;
let version = null;
let selected = null; // { id, file }

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const save = () => localStorage.setItem(STORE, JSON.stringify(state));
const cls = (status) => "s-" + status.replace(/ /g, "-");
const pill = (status) => '<span class="pill ' + cls(status) + '">' + esc(status) + "</span>";
const byId = (id) => data.rows.find((r) => r.id === id);

// ---- markdown (the subset the task files use)

function inline(text) {
  const keep = [];
  const hold = (html) => "\u0000" + (keep.push(html) - 1) + "\u0000";
  let s = text.replace(/`([^`]+)`/g, (_, code) => hold("<code>" + esc(code) + "</code>"));
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, href) => {
    const task = href.match(/(?:^|\/)(TASK-[\w.-]+\.md)$/);
    if (task) return hold('<a data-file="' + esc(task[1]) + '">' + inline(label) + "</a>");
    if (/^https?:/.test(href)) return hold('<a href="' + esc(href) + '" target="_blank" rel="noopener">' + inline(label) + "</a>");
    return hold('<span class="ref" title="' + esc(href) + '">' + inline(label) + "</span>");
  });
  s = esc(s)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*\w])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>")
    .replace(/(^|[^\w])_([^_\s][^_]*)_(?!\w)/g, "$1<em>$2</em>")
    .replace(/\bTASK-\d+[a-z]?\b/g, (id) => '<a data-id="' + id + '">' + id + "</a>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => keep[+i]);
}

function renderList(items) {
  // items: [{ indent, ordered, text }] → nested <ul>/<ol>
  let html = "";
  const stack = [];
  for (const item of items) {
    while (stack.length && item.indent < stack[stack.length - 1].indent) html += "</li></" + stack.pop().tag + ">";
    const top = stack[stack.length - 1];
    if (!top || item.indent > top.indent) {
      const tag = item.ordered ? "ol" : "ul";
      stack.push({ indent: item.indent, tag });
      html += "<" + tag + ">";
    } else {
      html += "</li>";
    }
    const box = item.text.match(/^\[([ xX])\]\s+(.*)$/);
    html += box
      ? '<li class="task"><span class="box' + (box[1] === " " ? "" : " on") + '">' + (box[1] === " " ? "" : "✓") + "</span>" + inline(box[2])
      : "<li>" + inline(item.text);
  }
  while (stack.length) html += "</li></" + stack.pop().tag + ">";
  return html;
}

function markdown(src) {
  const lines = src.replace(/\r/g, "").split("\n");
  const out = [];
  let para = [];
  const flush = () => { if (para.length) out.push("<p>" + inline(para.join(" ")) + "</p>"); para = []; };
  const LIST = /^(\s*)([-*+]|\d+\.)\s+(.*)$/;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*```/.test(line)) {
      flush();
      const code = [];
      while (++i < lines.length && !/^\s*```/.test(lines[i])) code.push(lines[i]);
      out.push("<pre><code>" + esc(code.join("\n")) + "</code></pre>");
    } else if (/^#{1,6}\s/.test(line)) {
      flush();
      const level = line.match(/^#+/)[0].length;
      out.push("<h" + level + ">" + inline(line.slice(level).trim()) + "</h" + level + ">");
    } else if (/^\s*\|/.test(line) && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1] || "")) {
      flush();
      const cells = (l) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => inline(c.trim()));
      let html = "<table><thead><tr>" + cells(line).map((c) => "<th>" + c + "</th>").join("") + "</tr></thead><tbody>";
      i++;
      while (i + 1 < lines.length && /^\s*\|/.test(lines[i + 1])) html += "<tr>" + cells(lines[++i]).map((c) => "<td>" + c + "</td>").join("") + "</tr>";
      out.push(html + "</tbody></table>");
    } else if (LIST.test(line)) {
      flush();
      const items = [];
      for (; i < lines.length; i++) {
        const m = lines[i].match(LIST);
        if (m) items.push({ indent: m[1].replace(/\t/g, "  ").length, ordered: /\d/.test(m[2]), text: m[3] });
        else if (/^\s+\S/.test(lines[i]) && items.length) items[items.length - 1].text += " " + lines[i].trim();
        else { i--; break; }
      }
      out.push(renderList(items));
    } else if (/^>\s?/.test(line)) {
      flush();
      out.push("<blockquote>" + inline(line.replace(/^>\s?/, "")) + "</blockquote>");
    } else if (!line.trim()) {
      flush();
    } else {
      para.push(line.trim());
    }
  }
  flush();
  return out.join("\n");
}

// ---- filtering + sorting

function idKey(id) {
  const m = id.match(/TASK-(\d+)([a-z]?)/);
  return m ? +m[1] * 100 + (m[2] ? m[2].charCodeAt(0) - 96 : 0) : 0;
}

function sortValue(row, key) {
  switch (key) {
    case "id": return idKey(row.id);
    case "status": return data.statuses.indexOf(row.status);
    case "hard": return row.hard.length * 1000 + row.soft.length;
    case "dependents": return row.dependents.length;
    case "title": case "layers": case "model": return row[key].toLowerCase();
    default: return row.order;
  }
}

function matches(row, ignoreStatus) {
  if (!ignoreStatus && !state.statuses.includes(row.status)) return false;
  if (state.model && row.model !== state.model) return false;
  const words = state.query.toLowerCase().split(/\s+/).filter(Boolean);
  const hay = [row.id, row.title, row.status_text, row.depends, row.layers, row.model].join(" ").toLowerCase();
  return words.every((w) => hay.includes(w));
}

function visibleRows() {
  const dir = state.desc ? -1 : 1;
  return data.rows.filter((r) => matches(r)).sort((a, b) => {
    const va = sortValue(a, state.sort);
    const vb = sortValue(b, state.sort);
    return (va < vb ? -1 : va > vb ? 1 : a.order - b.order) * dir;
  });
}

// ---- pieces

function titleOf(id) {
  const r = byId(id);
  return r ? r.title.replace(/`/g, "") + " (" + r.status + ")" : "unknown task";
}

function depChips(row, compact) {
  const done = (id) => { const r = byId(id); return r && r.status === "done"; };
  const hard = row.hard.filter((id) => !compact || !done(id));
  const chips = hard.map((id) => '<a class="chip ' + (done(id) ? "done" : "pending") + '" data-id="' + id + '" title="' + esc(titleOf(id)) + '">' + id + "</a>");
  if (!compact) chips.push(...row.soft.map((id) => '<a class="chip soft" data-id="' + id + '" title="soft: ' + esc(titleOf(id)) + '">' + id + "</a>"));
  return chips.join("");
}

function unblockChips(row) {
  return row.dependents.map((id) => '<a class="chip unblock" data-id="' + id + '" title="' + esc(titleOf(id)) + '">' + id + "</a>").join("");
}

const modelBadge = (row) => row.model ? '<span class="model ' + esc(row.model) + '" title="' + esc(row.model_note) + '">' + esc(row.model) + "</span>" : "";

function relation(id) {
  const sel = selected && byId(selected.id);
  if (!sel) return "";
  if (id === sel.id) return "selected";
  if (sel.hard.includes(id)) return "dep";
  if (sel.dependents.includes(id)) return "unblocks";
  return "";
}

// ---- views

function renderTable(rows) {
  $("#table tbody").innerHTML = rows.map((row) => {
    const extra = row.status_text.slice(row.status.length).trim();
    const deps = depChips(row, false);
    const unblocks = unblockChips(row);
    return '<tr data-row="' + row.id + '" class="' + relation(row.id) + '">' +
      '<td class="order">' + (row.order + 1) + "</td>" +
      '<td class="id">' + (row.file ? row.id : '<span class="nofile" title="no task file yet">' + row.id + "</span>") + "</td>" +
      '<td class="title">' + inline(row.title) + "</td>" +
      '<td class="status">' + pill(row.status) + (extra ? '<span class="extra">' + inline(extra) + "</span>" : "") + "</td>" +
      '<td class="deps" title="' + esc(row.depends) + '">' + (deps ? '<div class="chips-cell">' + deps + "</div>" : '<span class="none">' + inline(row.depends) + "</span>") + "</td>" +
      '<td class="dependents">' + (unblocks ? '<div class="chips-cell">' + unblocks + "</div>" : "") + "</td>" +
      '<td class="layers">' + inline(row.layers) + "</td>" +
      '<td class="model-cell">' + modelBadge(row) + "</td></tr>";
  }).join("");
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    th.classList.toggle("sorted", th.dataset.sort === state.sort);
    th.classList.toggle("desc", th.dataset.sort === state.sort && state.desc);
  });
}

function renderBoard(rows) {
  const columns = data.statuses.filter((s) => state.statuses.includes(s));
  $("#board").innerHTML = columns.map((s) => {
    const cards = rows.filter((r) => r.status === s);
    return '<section class="column ' + cls(s) + (cards.length ? "" : " empty-col") + '"><div class="column-head"><span>' + esc(s) + '</span><span class="n">' + cards.length + "</span></div>" +
      '<div class="cards">' + cards.map((row) => {
        const pending = depChips(row, true);
        return '<div class="card ' + relation(row.id) + '" data-row="' + row.id + '"><div class="card-top"><span>' + row.id + "</span>" + modelBadge(row) + "</div>" +
          '<div class="card-title">' + inline(row.title) + "</div>" +
          (pending ? '<div class="chips-cell"><span class="label">waits for</span>' + pending + "</div>" : "") + "</div>";
      }).join("") + (cards.length ? "" : '<div class="none">no tasks</div>') + "</div></section>";
  }).join("");
}

function renderHeader() {
  const counts = {};
  data.rows.forEach((r) => { counts[r.status] = (counts[r.status] || 0) + 1; });
  const present = data.statuses.filter((s) => counts[s]);
  $("#summary").innerHTML = "<b>" + (counts.done || 0) + "</b> of " + data.rows.length + " done · <b>" +
    ((counts["in progress"] || 0) + (counts["to playtest"] || 0)) + "</b> in flight · <b>" + (counts.ready || 0) + "</b> ready";
  $("#progress").innerHTML = ["done", "to playtest", "in progress", "ready", "blocked", "idea", "merged"].filter((s) => counts[s]).map((s) =>
    '<span class="' + cls(s) + '" style="flex: ' + counts[s] + '" title="' + s + ": " + counts[s] + '"></span>').join("");
  $("#chips").innerHTML = present.map((s) =>
    '<button type="button" class="fchip ' + cls(s) + (state.statuses.includes(s) ? " on" : "") + '" data-status="' + s + '" title="Click: show / hide · Alt+click: only this">' +
    '<span class="dot"></span>' + esc(s) + '<span class="n">' + counts[s] + "</span></button>").join("");
  const isOpen = state.statuses.length === OPEN.length && OPEN.every((s) => state.statuses.includes(s));
  const isAll = present.every((s) => state.statuses.includes(s));
  document.querySelectorAll("[data-preset]").forEach((b) => b.classList.toggle("on", b.dataset.preset === "open" ? isOpen : isAll && !isOpen));
  document.querySelectorAll("[data-view]").forEach((b) => b.classList.toggle("on", b.dataset.view === state.view));
  const models = [...new Set(data.rows.map((r) => r.model).filter(Boolean))].sort();
  $("#model").innerHTML = '<option value="">Any model</option>' + models.map((m) => "<option" + (m === state.model ? " selected" : "") + ' value="' + esc(m) + '">' + esc(m) + "</option>").join("");
}

function renderBody() {
  const rows = visibleRows();
  const board = state.view === "board";
  $("#table").hidden = board || !rows.length;
  $("#board").hidden = !board;
  $("#nothing").hidden = rows.length > 0;
  if (board) renderBoard(rows); else renderTable(rows);
  const filtered = data.rows.filter((r) => matches(r, true)).length;
  $("#count").textContent = rows.length + " shown" + (filtered !== data.rows.length ? " · " + filtered + " match the search" : "");
}

function render() {
  renderHeader();
  renderBody();
  $("#notes").innerHTML = markdown(data.intro + "\n\n" + data.notes);
}

// ---- task panel

function renderFacts(row) {
  if (!row) return "";
  const deps = depChips(row, false);
  const unblocks = unblockChips(row);
  return '<dl class="facts">' +
    "<dt>Depends on</dt><dd>" + (deps ? '<div class="chips-cell">' + deps + '<span class="legend"><i style="background: var(--bad)"></i>marked red in the list</span></div>' : inline(row.depends)) + "</dd>" +
    "<dt>Unblocks</dt><dd>" + (unblocks ? '<div class="chips-cell">' + unblocks + '<span class="legend"><i style="background: var(--ok)"></i>marked green in the list</span></div>' : '<span class="muted">nothing</span>') + "</dd>" +
    (row.layers ? "<dt>Layers</dt><dd>" + inline(row.layers) + "</dd>" : "") +
    (row.model_note ? "<dt>Model</dt><dd>" + inline(row.model_note) + "</dd>" : "") +
    "<dt>Priority</dt><dd>#" + (row.order + 1) + " in BACKLOG.md</dd></dl>";
}

async function openTask(id, file) {
  selected = { id, file };
  history.replaceState(null, "", location.search + "#" + id);
  renderBody();
  const row = byId(id);
  $("#detail").hidden = false;
  document.body.classList.add("detail-open");
  $("#detail-id").textContent = id;
  $("#detail-status").innerHTML = row ? pill(row.status) : "";
  $("#detail-facts").innerHTML = renderFacts(row);
  if (!file) {
    $("#detail-body").innerHTML = row ? markdown("# " + row.title + "\n\n*No task file yet – this is an idea in BACKLOG.md.*") : "<p>Unknown task.</p>";
    return;
  }
  const res = await fetch("/api/task/" + encodeURIComponent(file));
  if (!selected || selected.file !== file) return;
  if (!res.ok) {
    $("#detail-body").innerHTML = "<p>Could not load " + esc(file) + ".</p>";
    return;
  }
  // the facts above replace the file's header list (Status / Layers / Depends on / Model)
  const text = (await res.text()).replace(/^(# .*\n)\n?(?:- \*\*[^*]+\*\*:.*\n)+/, "$1").replace(/^# TASK-\w+:\s*/, "# ");
  $("#detail-body").innerHTML = markdown(text);
}

function openId(id) {
  const row = byId(id);
  openTask(id, row ? row.file : null);
  const el = document.querySelector('[data-row="' + id + '"]');
  if (el) el.scrollIntoView({ block: "nearest" });
}

function closeTask() {
  selected = null;
  $("#detail").hidden = true;
  document.body.classList.remove("detail-open");
  history.replaceState(null, "", location.pathname + location.search);
  renderBody();
}

// ---- data + live reload

async function load() {
  const res = await fetch("/api/backlog");
  if (!res.ok) throw new Error("backlog " + res.status);
  data = await res.json();
  version = data.version;
  render();
}

async function poll() {
  const live = $("#live");
  try {
    const res = await fetch("/api/version");
    const v = (await res.json()).version;
    live.classList.remove("offline");
    live.textContent = "Live";
    if (v !== version) {
      await load();
      if (selected) {
        const row = byId(selected.id);
        openTask(selected.id, row ? row.file : selected.file);
      }
      live.classList.add("flash");
      live.title = "Updated " + new Date().toLocaleTimeString();
      setTimeout(() => live.classList.remove("flash"), 900);
    }
  } catch (err) {
    live.classList.add("offline");
    live.textContent = "Offline";
    live.title = "Server not reachable (tools/backlog_view.sh stopped?)";
  }
  setTimeout(poll, POLL_MS);
}

// ---- events

document.addEventListener("click", (ev) => {
  const link = ev.target.closest("a[data-id], a[data-file]");
  if (link) {
    ev.preventDefault();
    ev.stopPropagation();
    if (link.dataset.file) {
      const row = data.rows.find((r) => r.file === link.dataset.file);
      openTask(row ? row.id : link.dataset.file.replace(/^(TASK-\d+[a-z]?).*/, "$1"), link.dataset.file);
    } else {
      openId(link.dataset.id);
    }
    return;
  }
  const chip = ev.target.closest("[data-status]");
  if (chip) {
    const s = chip.dataset.status;
    if (ev.altKey || ev.ctrlKey || ev.metaKey) state.statuses = [s];
    else state.statuses = state.statuses.includes(s) ? state.statuses.filter((x) => x !== s) : state.statuses.concat(s);
  }
  const preset = ev.target.closest("[data-preset]");
  if (preset) state.statuses = preset.dataset.preset === "all" ? data.statuses.slice() : OPEN.slice();
  const view = ev.target.closest("[data-view]");
  if (view) state.view = view.dataset.view;
  const th = ev.target.closest("th[data-sort]");
  if (th) {
    state.desc = state.sort === th.dataset.sort ? !state.desc : false;
    state.sort = th.dataset.sort;
  }
  if (chip || preset || th || view) { save(); renderHeader(); renderBody(); return; }
  const item = ev.target.closest("[data-row]");
  if (item) {
    if (selected && selected.id === item.dataset.row) closeTask();
    else openId(item.dataset.row);
  }
});

$("#search").value = state.query;
$("#search").addEventListener("input", (ev) => { state.query = ev.target.value; save(); renderBody(); });
$("#model").addEventListener("change", (ev) => { state.model = ev.target.value; save(); renderBody(); });
$("#reset").addEventListener("click", () => {
  Object.assign(state, { sort: "order", desc: false, statuses: OPEN.slice(), query: "", model: "" });
  $("#search").value = "";
  save();
  render();
});
$("#notes-toggle").addEventListener("click", (ev) => {
  $("#notes").hidden = !$("#notes").hidden;
  ev.target.classList.toggle("on", !$("#notes").hidden);
});
$("#detail-close").addEventListener("click", closeTask);
document.addEventListener("keydown", (ev) => {
  const typing = ev.target.closest("input, select, textarea");
  if (ev.key === "/" && !typing) { ev.preventDefault(); $("#search").focus(); }
  else if (ev.key === "Escape") { if (typing) ev.target.blur(); else closeTask(); }
  else if (!typing && !ev.ctrlKey && !ev.metaKey && (ev.key === "b" || ev.key === "t")) {
    state.view = ev.key === "b" ? "board" : "table";
    save();
    renderHeader();
    renderBody();
  }
});

load().then(() => {
  const id = location.hash.slice(1);
  if (id) openId(id);
  setTimeout(poll, POLL_MS);
}).catch(() => { $("#live").classList.add("offline"); setTimeout(poll, POLL_MS); });
