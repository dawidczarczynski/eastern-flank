"use strict";
// Backlog viewer: docs/tasks/BACKLOG.md as a table, a board or a dependency tree per topic, with sorting, filters and a task file panel.
// Polls /api/version every second and re-renders when a file changed.

const STORE = "backlog_view.state.v2";
const POLL_MS = 1000;
const OPEN = ["in progress", "to playtest", "ready", "blocked", "idea"];
const state = Object.assign(
  { sort: "order", desc: false, statuses: OPEN.slice(), query: "", model: "", view: "table", folded: [] },
  JSON.parse(localStorage.getItem(STORE) || "{}")
);
const VIEWS = ["table", "board", "tree"];
const urlView = new URLSearchParams(location.search).get("view"); // ?view=board / ?view=table / ?view=tree
if (VIEWS.includes(urlView)) state.view = urlView;
let data = null;
let version = null;
let selected = null; // { id, file }
// Inside the devtools hub (tools/devtools): its Claude chat state, sent by the parent page with postMessage
let hub = null; // { available, tasks: { TASK-ID: chat state } }
const IMPLEMENTABLE = ["ready", "in progress", "to playtest"];

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
    case "usage": return row.usage ? row.usage.cost : -1;
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

// ---- usage (tools/usage_forecast.py): weighted cost of a task, as % of the subscription windows once calibrated

const UNCALIBRATED = "uncalibrated – run tasks from devtools (▶ Implement with Claude) to calibrate";
const money = (v) => "$" + (v >= 10 ? v.toFixed(0) : v.toFixed(1));
const pctOf = (v) => (v >= 10 ? Math.round(v) : Math.round(v * 10) / 10) + " %";
const clock = (epoch) => new Date(epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

// "~15–30 % · ~3–6 % wk" (forecast) / "12 % · 2 % wk" (actual); "" while the 5-hour window is uncalibrated
function usagePct(u) {
  const part = (w, suffix) => {
    const v = u.pct[w];
    if (v == null) return "";
    return (Array.isArray(v) ? "~" + pctOf(v[0]).replace(" %", "") + "–" + pctOf(v[1]) : pctOf(v)) + suffix;
  };
  return u.pct.five_hour == null ? "" : [part("five_hour", ""), part("seven_day", " wk")].filter(Boolean).join(" · ");
}

function usageTitle(u) {
  if (u.kind === "actual") {
    return "Actual: " + money(u.cost) + " API-equivalent (weighted tokens), " + u.sessions + " session(s), " + u.active_hours + " h" +
      (u.orchestrator ? ", orchestrator on " + u.orchestrator : "");
  }
  const lines = ["Forecast: " + money(u.low) + "–" + money(u.high) + " API-equivalent (median " + money(u.mid) + ")",
    "Compared with " + u.basis.length + " finished task(s) – " + (u.low_confidence ? "low confidence, too few in " + u.group : u.group),
    historyNote(u)];
  if (u.spent) lines.push("Already spent " + money(u.spent) + " (subtracted)");
  if (!usagePct(u)) lines.push("Percentages " + UNCALIBRATED);
  return lines.join("\n");
}

const historyNote = (u) => u.history === "all" ? "History: all finished tasks (too few with a sonnet orchestrator yet)" : "History: tasks whose orchestrator ran on " + u.history;

const fitWarning = (u) => u.wont_fit ? '<span class="wont-fit" title="May not fit before the 5-hour reset at ' + clock(u.wont_fit) + '">⚠</span>' : "";

function usageCell(row) {
  const u = row.usage;
  if (!u) return "";
  const pct = usagePct(u);
  const badge = '<span class="size size-' + u.class + (u.kind === "actual" ? " actual" : "") + '">' + u.class + "</span>";
  const body = u.kind === "actual" ? badge + '<span class="usage-actual">' + (pct || money(u.cost)) + "</span>"
    : pct ? '<span class="usage-pct">' + pct + "</span>" : badge;
  return '<span class="usage' + (u.kind === "forecast" && u.low_confidence ? " low-conf" : "") + '" title="' + esc(usageTitle(u)) + '">' + body +
    (u.kind === "forecast" && u.low_confidence ? '<span class="conf">?</span>' : "") + "</span>" + fitWarning(u);
}

function usageFacts(row) {
  const u = row.usage;
  if (!u) return "";
  if (u.kind === "actual") {
    return "<dt>Usage</dt><dd>" + usageCell(row) + ' <span class="muted">actual · ' + money(u.cost) + " API-equivalent · " + u.sessions + " session(s) · " + u.active_hours + " h</span></dd>";
  }
  const basis = u.basis.map((b) => '<a class="chip" data-id="' + b.id + '" title="' + esc(titleOf(b.id)) + '">' + b.id + " · " + money(b.cost) + "</a>").join("");
  return "<dt>Usage</dt><dd>" + usageCell(row) + ' <span class="muted">' + (usagePct(u) ? "" : UNCALIBRATED + "<br>") +
    "forecast " + money(u.low) + "–" + money(u.high) + " API-equivalent" + (u.spent ? " left (" + money(u.spent) + " spent)" : "") +
    " · " + (u.low_confidence ? "low confidence (fewer than 3 finished " + esc(u.group) + " tasks: all used)" : esc(u.group)) +
    (u.scale !== 1 ? " · size × " + u.scale : "") + " · " + esc(historyNote(u)) + (u.wont_fit ? " · may not fit before the reset at " + clock(u.wont_fit) : "") +
    '</span><div class="chips-cell basis">' + basis + "</div></dd>";
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
      '<td class="model-cell">' + modelBadge(row) + "</td>" +
      '<td class="usage-cell">' + usageCell(row) + "</td></tr>";
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

// Tree: one lane per topic, a left-to-right diagram in it – each task right of the dependency it builds on,
// joined by curves; other dependencies in the topic as dashed curves. A task that does not match the filters
// still shows as a small tag while something right of it does, so the branches keep their shape; a run of
// such tags in a row folds into one (`037 … 047`).
const TREE = { w: 232, h: 70, tagW: 92, chainW: 132, tagH: 26, gapX: 54, gapY: 10, gapRoot: 22, pad: 14 };

function layoutTopic(topic, shown, folded) {
  const boxes = {};
  let cursor = TREE.pad;
  let depthMax = 0;
  const visible = (node) => shown.has(node.id) || node.children.some(visible);
  const shift = (node, dy) => { const b = boxes[node.id]; if (!b) return; b.y += dy; b.kids.forEach((k) => shift(k, dy)); };
  const visibleKids = (node) => folded.has(node.id) ? [] : node.children.filter(visible);
  function place(start, depth) {
    const chain = [start];
    let node = start;
    while (!shown.has(node.id) && visibleKids(node).length === 1 && !shown.has(visibleKids(node)[0].id)) {
      node = visibleKids(node)[0];
      chain.push(node);
    }
    const full = shown.has(node.id);
    const kids = visibleKids(node);
    const h = full ? TREE.h : TREE.tagH;
    const w = full ? TREE.w : chain.length > 1 ? TREE.chainW : TREE.tagW;
    const box = { node, chain, full, depth, w, h, kids, x: TREE.pad + depth * (TREE.w + TREE.gapX), y: 0 };
    chain.forEach((n) => { boxes[n.id] = box; });
    depthMax = Math.max(depthMax, depth);
    const top = cursor;
    if (!kids.length) {
      box.y = cursor;
      cursor += h + TREE.gapY;
      return;
    }
    kids.forEach((k) => place(k, depth + 1));
    const first = boxes[kids[0].id];
    const last = boxes[kids[kids.length - 1].id];
    box.y = (first.y + first.h / 2 + last.y + last.h / 2) / 2 - h / 2;
    if (box.y < top) { const dy = top - box.y; box.y = top; kids.forEach((k) => shift(k, dy)); cursor += dy; }
    cursor = Math.max(cursor, box.y + h + TREE.gapY);
  }
  topic.roots.filter(visible).forEach((root) => { place(root, 0); cursor += TREE.gapRoot - TREE.gapY; });
  return { boxes, width: TREE.pad * 2 + (depthMax + 1) * TREE.w + depthMax * TREE.gapX, height: cursor - TREE.gapRoot + TREE.gapY + TREE.pad };
}

function curve(a, b, cls, from, to) {
  const x1 = a.x + a.w;
  const y1 = a.y + a.h / 2;
  const x2 = b.x;
  const y2 = b.y + b.h / 2;
  const mx = (x1 + x2) / 2;
  const d = x2 > x1
    ? "M" + x1 + " " + y1 + " C" + mx + " " + y1 + " " + mx + " " + y2 + " " + x2 + " " + y2
    : "M" + x1 + " " + y1 + " C" + (x1 + 60) + " " + y1 + " " + (x2 - 60) + " " + y2 + " " + x2 + " " + y2; // a link back to the left
  return '<path class="' + cls + '" data-a="' + from + '" data-b="' + to + '" d="' + d + '"/>';
}

function treeCard(box) {
  const node = box.node;
  const row = byId(node.id);
  const style = 'style="left:' + box.x + "px;top:" + box.y + 'px"';
  const hiddenKids = node.children.length && !box.kids.length ? countNodes(node) : 0;
  const fold = node.children.length
    ? '<button type="button" class="fold" data-fold="' + node.id + '" title="' + (hiddenKids ? "Unfold" : "Fold") + ' the branch">' + (hiddenKids ? "+" + hiddenKids : "−") + "</button>"
    : "";
  const tip = esc(node.id + " · " + row.status + "\n" + row.title.replace(/`/g, ""));
  if (!box.full) {
    const short = (id) => id.replace("TASK-", "");
    const chain = box.chain.length > 1;
    const label = chain ? short(box.chain[0].id) + " … " + short(node.id) + '<span class="n">' + box.chain.length + "</span>" : short(node.id);
    const chainTip = esc(box.chain.map((n) => n.id + " · " + byId(n.id).status + " – " + byId(n.id).title.replace(/`/g, "")).join("\n"));
    return '<div class="tnode tag ' + (chain ? "chain " : "") + cls(row.status) + " " + relation(node.id) + '" data-row="' + node.id + '" title="' + (chain ? chainTip : tip) + '" ' +
      'style="left:' + box.x + "px;top:" + box.y + "px;width:" + box.w + 'px">' +
      '<span class="dot"></span><span class="node-id">' + label + "</span>" + fold + "</div>";
  }
  const done = (id) => { const r = byId(id); return r && r.status === "done"; };
  const ext = node.external.filter((e) => !done(e.id));
  const extHtml = ext.length
    ? '<span class="ext" title="' + esc(ext.map((e) => e.id + " – " + e.topic).join("\n")) + '">← ' + ext.map((e) => '<a data-id="' + e.id + '">' + e.id.replace("TASK-", "") + "</a>").join(" ") + "</span>"
    : "";
  return '<div class="tnode card-node ' + cls(row.status) + " " + relation(node.id) + '" data-row="' + node.id + '" title="' + tip + '" ' + style + '>' +
    '<div class="tn-top"><span class="dot"></span><span class="node-id">' + node.id + '</span><span class="st">' + esc(row.status) + "</span>" + extHtml + fold + "</div>" +
    '<div class="tn-title">' + inline(row.title) + "</div></div>";
}

const countNodes = (node) => node.children.reduce((n, c) => n + 1 + countNodes(c), 0);
const allIds = (node) => [node.id].concat(...node.children.map(allIds));

function renderTree(rows) {
  const shown = new Set(rows.map((r) => r.id));
  const folded = new Set(state.folded);
  $("#tree").innerHTML = data.tree.map((topic) => {
    const ids = [].concat(...topic.roots.map(allIds));
    const nShown = ids.filter((id) => shown.has(id)).length;
    if (!nShown) return "";
    const counts = {};
    ids.forEach((id) => { const s = byId(id).status; counts[s] = (counts[s] || 0) + 1; });
    const bar = ["done", "to playtest", "in progress", "ready", "blocked", "idea", "merged"].filter((s) => counts[s]).map((s) =>
      '<span class="' + cls(s) + '" style="flex: ' + counts[s] + '" title="' + s + ": " + counts[s] + '"></span>').join("");
    const key = "topic:" + topic.name;
    const open = !folded.has(key);
    let body = "";
    if (open) {
      const lay = layoutTopic(topic, shown, folded);
      const boxes = [...new Set(Object.values(lay.boxes))];
      let paths = "";
      boxes.forEach((b) => {
        b.kids.forEach((k) => { paths += curve(b, lay.boxes[k.id], "tree-edge " + cls(byId(k.id).status), b.node.id, k.id); });
        b.node.also.forEach((id) => { if (lay.boxes[id] && lay.boxes[id] !== b) paths += curve(lay.boxes[id], b, "also-edge", id, b.node.id); });
      });
      body = '<div class="lane" style="width:' + lay.width + "px;height:" + lay.height + 'px">' +
        '<svg width="' + lay.width + '" height="' + lay.height + '">' + paths + "</svg>" + boxes.map(treeCard).join("") + "</div>";
    }
    return '<section class="topic' + (open ? "" : " folded") + '">' +
      '<div class="topic-head" data-fold="' + esc(key) + '"><span class="chev">' + (open ? "▾" : "▸") + "</span>" +
      "<h2>" + esc(topic.name) + "</h2>" +
      '<span class="n">' + (counts.done || 0) + " / " + ids.length + " done" + (nShown !== ids.length ? " · " + nShown + " shown" : "") + "</span>" +
      '<div class="progress">' + bar + "</div></div>" + body + "</section>";
  }).join("");
}

// hovering a task lights up its links in the diagram
document.addEventListener("mouseover", (ev) => {
  const node = ev.target.closest(".tnode");
  const id = node ? node.dataset.row : null;
  document.querySelectorAll("#tree path.hot").forEach((p) => p.classList.remove("hot"));
  if (id) document.querySelectorAll('#tree path[data-a="' + id + '"], #tree path[data-b="' + id + '"]').forEach((p) => p.classList.add("hot"));
});

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
  $("#table").hidden = state.view !== "table" || !rows.length;
  $("#board").hidden = state.view !== "board";
  $("#tree").hidden = state.view !== "tree" || !rows.length;
  $("#nothing").hidden = rows.length > 0;
  if (state.view === "board") renderBoard(rows);
  else if (state.view === "tree") renderTree(rows);
  else renderTable(rows);
  const filtered = data.rows.filter((r) => matches(r, true)).length;
  $("#count").textContent = rows.length + " shown" + (filtered !== data.rows.length ? " · " + filtered + " match the search" : "");
}

function renderUsageHeader() {
  const u = data.usage;
  const calibrated = u.calibration.five_hour.percent_per_cost != null;
  const scanned = u.costs_scanned ? "costs scanned " + new Date(u.costs_scanned * 1000).toLocaleString() : "no task_costs.json yet";
  const cal = Object.entries(u.calibration).map(([w, f]) => w + ": " + (f.percent_per_cost == null ? f.sessions + "/" + u.min_samples + " sessions" : f.percent_per_cost.toFixed(2) + " % per $")).join(", ");
  $("#th-usage").title = "Expected (open tasks) or actual (finished) Claude usage of /implement-task.\n" +
    (calibrated ? "% of the 5-hour window · % of the week" : "Size S–XL by quartiles of finished tasks – percentages " + UNCALIBRATED) +
    "\nCalibration " + cal + "\n" + scanned;
  $("#costs-refresh").title = "Re-scan the Claude Code transcripts into docs/tasks/task_costs.json (" + scanned + ")";
}

function render() {
  renderHeader();
  renderUsageHeader();
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
    usageFacts(row) +
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
  renderClaude();
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

function renderClaude() {
  const box = $("#detail-claude");
  const row = selected && byId(selected.id);
  if (!hub || !hub.available || !row) { box.innerHTML = ""; return; }
  const chat = hub.tasks[row.id];
  if (chat) {
    box.innerHTML = '<button type="button" class="btn sm claude-btn" data-claude="open-chat" title="Open this task\'s Claude chat in devtools">' +
      (chat === "working" ? '<span class="spinner"></span> Claude working' : "✦ Open chat") + "</button>";
  } else if (IMPLEMENTABLE.includes(row.status) && row.file) {
    const u = row.usage && row.usage.kind === "forecast" ? row.usage : null;
    const estimate = u ? '<span class="usage-estimate" title="' + esc(usageTitle(u)) + '">' + (usagePct(u) || "size " + u.class + " · " + money(u.low) + "–" + money(u.high)) + fitWarning(u) + "</span>" : "";
    box.innerHTML = estimate + '<button type="button" class="btn sm primary" data-claude="implement" title="Run /implement-task ' + row.id + ' in a Claude Code chat (devtools)">▶ Implement with Claude</button>';
  } else if (row.status === "idea") {
    box.innerHTML = '<button type="button" class="btn sm primary" data-claude="design" title="Hand this idea to the game-designer agent: it writes the task file and updates the backlog row (devtools)">✎ Design with game-designer</button>';
  } else {
    box.innerHTML = "";
  }
}

if (window.parent !== window) {
  window.addEventListener("message", (ev) => {
    if (ev.source !== window.parent || !ev.data || ev.data.type !== "devtools:chats") return;
    hub = ev.data;
    renderClaude();
  });
  window.parent.postMessage({ type: "devtools:hello" }, "*");
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
  const claude = ev.target.closest("[data-claude]");
  if (claude && selected) {
    // the hub checks the sender's origin; the message carries only the task id
    window.parent.postMessage({ type: "devtools:" + claude.dataset.claude, task: selected.id }, "*");
    return;
  }
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
  const fold = ev.target.closest("[data-fold]");
  if (fold) {
    const key = fold.dataset.fold;
    state.folded = state.folded.includes(key) ? state.folded.filter((k) => k !== key) : state.folded.concat(key);
    save();
    renderBody();
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
$("#costs-refresh").addEventListener("click", async (ev) => {
  const btn = ev.currentTarget;
  btn.disabled = true;
  btn.textContent = "Scanning…";
  try {
    const res = await fetch("/api/costs/refresh", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    if (!res.ok) alert("Cost scan failed: " + ((await res.json()).error || res.status));
  } finally {
    btn.disabled = false;
    btn.textContent = "↻ Costs";
  }
});
document.addEventListener("keydown", (ev) => {
  const typing = ev.target.closest("input, select, textarea");
  if (ev.key === "/" && !typing) { ev.preventDefault(); $("#search").focus(); }
  else if (ev.key === "Escape") { if (typing) ev.target.blur(); else closeTask(); }
  else if (!typing && !ev.ctrlKey && !ev.metaKey && !ev.altKey && ["b", "t", "r"].includes(ev.key)) {
    state.view = { b: "board", t: "table", r: "tree" }[ev.key];
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
