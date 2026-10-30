"use strict";
// Backlog viewer: table of docs/tasks/BACKLOG.md with sorting, filters and a task file panel.
// Polls /api/version every second and re-renders when a file changed.

const STORE = "backlog_view.state";
const POLL_MS = 1000;
const state = Object.assign(
  { sort: "order", desc: false, statuses: null, query: "", model: "" },
  JSON.parse(localStorage.getItem(STORE) || "{}")
);
let data = null;
let version = null;
let selected = null; // { id, file }

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const save = () => localStorage.setItem(STORE, JSON.stringify(state));
const cls = (status) => "s-" + status.replace(/ /g, "-");

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
      ? '<li class="task">' + (box[1] === " " ? "☐ " : "☑ ") + inline(box[2])
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

// ---- table

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

function visibleRows() {
  const words = state.query.toLowerCase().split(/\s+/).filter(Boolean);
  const rows = data.rows.filter((row) => {
    if (!state.statuses.includes(row.status)) return false;
    if (state.model && row.model !== state.model) return false;
    const hay = [row.id, row.title, row.status_text, row.depends, row.layers, row.model].join(" ").toLowerCase();
    return words.every((w) => hay.includes(w));
  });
  const dir = state.desc ? -1 : 1;
  return rows.sort((a, b) => {
    const va = sortValue(a, state.sort);
    const vb = sortValue(b, state.sort);
    return (va < vb ? -1 : va > vb ? 1 : a.order - b.order) * dir;
  });
}

function depLinks(row) {
  const done = new Set(data.rows.filter((r) => r.status === "done").map((r) => r.id));
  const hard = row.hard.map((id) => '<a data-id="' + id + '" class="' + (done.has(id) ? "done" : "pending") + '">' + id + "</a>");
  const soft = row.soft.map((id) => '<a data-id="' + id + '" class="soft">' + id + "</a>");
  const links = hard.concat(soft).join(" ");
  return links || '<span class="muted">' + inline(row.depends) + "</span>";
}

function renderTable() {
  const rows = visibleRows();
  const sel = selected && data.rows.find((r) => r.id === selected.id);
  const deps = new Set(sel ? sel.hard : []);
  const unblocks = new Set(sel ? sel.dependents : []);
  $("#table tbody").innerHTML = rows.map((row) => {
    const rowCls = [row.id === (sel && sel.id) ? "selected" : "", deps.has(row.id) ? "dep" : "", unblocks.has(row.id) ? "unblocks" : ""].join(" ");
    const extra = row.status_text.slice(row.status.length).trim();
    return '<tr data-row="' + row.id + '" class="' + rowCls + '">' +
      '<td class="order">' + (row.order + 1) + "</td>" +
      '<td class="id">' + (row.file ? row.id : '<span class="nofile" title="no task file">' + row.id + "</span>") + "</td>" +
      '<td class="title">' + inline(row.title) + "</td>" +
      '<td class="status ' + cls(row.status) + '">' + (data.icons[row.status] || "") + " " + row.status +
        (extra ? ' <span class="extra">' + inline(extra) + "</span>" : "") + "</td>" +
      '<td class="deps" title="' + esc(row.depends) + '">' + depLinks(row) + "</td>" +
      '<td class="dependents">' + row.dependents.map((id) => '<a data-id="' + id + '">' + id + "</a>").join(" ") + "</td>" +
      '<td class="layers">' + inline(row.layers) + "</td>" +
      '<td class="model" title="' + esc(row.model_note) + '">' + esc(row.model) + "</td></tr>";
  }).join("");
  $("#count").textContent = rows.length + " / " + data.rows.length + " tasks";
  document.querySelectorAll("th[data-sort]").forEach((th) => {
    th.classList.toggle("sorted", th.dataset.sort === state.sort);
    th.classList.toggle("desc", th.dataset.sort === state.sort && state.desc);
  });
}

function renderChips() {
  const counts = {};
  data.rows.forEach((r) => { counts[r.status] = (counts[r.status] || 0) + 1; });
  const chips = data.statuses.filter((s) => counts[s]).map((s) =>
    '<button type="button" class="chip ' + cls(s) + (state.statuses.includes(s) ? " on" : "") + '" data-status="' + s + '" title="Click: toggle · Alt/Ctrl+click: only this">' +
    (data.icons[s] || "") + " " + s + ' <span class="n">' + counts[s] + "</span></button>");
  chips.push('<button type="button" data-preset="open" title="Everything except done and merged">open</button>');
  chips.push('<button type="button" data-preset="all">all</button>');
  $("#chips").innerHTML = chips.join("");
}

function renderModels() {
  const models = [...new Set(data.rows.map((r) => r.model).filter(Boolean))].sort();
  $("#model").innerHTML = '<option value="">any model</option>' +
    models.map((m) => '<option' + (m === state.model ? " selected" : "") + ">" + esc(m) + "</option>").join("");
}

function render() {
  renderChips();
  renderModels();
  renderTable();
  $("#notes").innerHTML = markdown(data.intro + "\n\n" + data.notes);
}

// ---- task panel

async function openTask(id, file) {
  selected = { id, file };
  history.replaceState(null, "", "#" + id);
  renderTable();
  const row = data.rows.find((r) => r.id === id);
  $("#detail").hidden = false;
  document.body.classList.add("detail-open");
  $("#detail-title").textContent = file || id;
  if (!file) {
    $("#detail-body").innerHTML = row
      ? markdown("# " + row.id + ": " + row.title + "\n\n- **Status**: " + row.status_text + "\n- **Depends on**: " + row.depends + "\n\n*No task file yet.*")
      : "<p>Unknown task.</p>";
    return;
  }
  const res = await fetch("/api/task/" + encodeURIComponent(file));
  if (selected && selected.file === file) $("#detail-body").innerHTML = res.ok ? markdown(await res.text()) : "<p>Could not load " + esc(file) + ".</p>";
}

function openId(id) {
  const row = data.rows.find((r) => r.id === id);
  openTask(id, row ? row.file : null);
  const tr = document.querySelector('tr[data-row="' + id + '"]');
  if (tr) tr.scrollIntoView({ block: "nearest" });
}

function closeTask() {
  selected = null;
  $("#detail").hidden = true;
  document.body.classList.remove("detail-open");
  history.replaceState(null, "", location.pathname);
  renderTable();
}

// ---- data + live reload

async function load() {
  const res = await fetch("/api/backlog");
  if (!res.ok) throw new Error("backlog " + res.status);
  data = await res.json();
  version = data.version;
  if (!state.statuses) state.statuses = data.statuses.slice();
  render();
}

async function poll() {
  const live = $("#live");
  try {
    const res = await fetch("/api/version");
    const v = (await res.json()).version;
    live.classList.remove("offline");
    live.title = "Live – reloads when BACKLOG.md or a task file changes";
    if (v !== version) {
      await load();
      if (selected) {
        const row = data.rows.find((r) => r.id === selected.id);
        openTask(selected.id, row ? row.file : selected.file);
      }
      live.classList.add("flash");
      live.title = "Updated " + new Date().toLocaleTimeString();
      setTimeout(() => live.classList.remove("flash"), 800);
    }
  } catch (err) {
    live.classList.add("offline");
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
  if (preset) state.statuses = data.statuses.filter((s) => preset.dataset.preset === "all" || !["done", "merged"].includes(s));
  const th = ev.target.closest("th[data-sort]");
  if (th) {
    state.desc = state.sort === th.dataset.sort ? !state.desc : false;
    state.sort = th.dataset.sort;
  }
  if (chip || preset || th) { save(); render(); return; }
  const tr = ev.target.closest("tr[data-row]");
  if (tr) {
    if (selected && selected.id === tr.dataset.row) closeTask();
    else openId(tr.dataset.row);
  }
});

$("#search").value = state.query;
$("#search").addEventListener("input", (ev) => { state.query = ev.target.value; save(); renderTable(); });
$("#model").addEventListener("change", (ev) => { state.model = ev.target.value; save(); renderTable(); });
$("#reset").addEventListener("click", () => {
  Object.assign(state, { sort: "order", desc: false, statuses: data.statuses.slice(), query: "", model: "" });
  $("#search").value = "";
  save();
  render();
});
$("#notes-toggle").addEventListener("click", (ev) => {
  $("#notes").hidden = !$("#notes").hidden;
  ev.target.classList.toggle("active", !$("#notes").hidden);
});
$("#detail-close").addEventListener("click", closeTask);
document.addEventListener("keydown", (ev) => {
  if (ev.key === "/" && document.activeElement !== $("#search")) { ev.preventDefault(); $("#search").focus(); }
  else if (ev.key === "Escape") { if (document.activeElement === $("#search")) $("#search").blur(); else closeTask(); }
});

load().then(() => {
  const id = location.hash.slice(1);
  if (id) openId(id);
  setTimeout(poll, POLL_MS);
}).catch(() => { $("#live").classList.add("offline"); setTimeout(poll, POLL_MS); });
