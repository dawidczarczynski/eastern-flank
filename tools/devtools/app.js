"use strict";
// Devtools hub: command-line tools as tiles + an activity panel with live output; a Claude Code chat; web tools as embedded pages.

const PARAMS_STORE = "devtools.params";
const GROUPS = {
  Verify: { color: "var(--accent)", text: "Before handing in a task" },
  Balance: { color: "var(--violet)", text: "Headless AI-vs-AI runs" },
  Visual: { color: "var(--teal)", text: "Renders – the images appear under Activity" },
  Game: { color: "var(--ok)", text: "Open a game or editor window" },
};
const ICONS = { ok: "✓", failed: "✕", cancelled: "–", queued: "…" };
const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const api = async (path, body) => {
  const res = await fetch(path, body === undefined ? {} : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || res.status);
  return data;
};

let services = [];
let commands = [];
let jobs = [];
let tab = "home";
let selectedJob = null; // { id, next, state, command, params }
let lastStates = null; // job id → state, for "finished" toasts
let chatInfo = { available: true, hint: "", commands: [] };
let chats = [];
let selectedChat = null; // { id, next, timer } – null: a new chat is being drafted
const savedParams = JSON.parse(localStorage.getItem(PARAMS_STORE) || "{}");

const toolUrl = (s) => location.protocol + "//" + location.hostname + ":" + s.port + "/";
const now = () => Date.now() / 1000;
const active = (job) => job.state === "running" || job.state === "queued";
const statusIcon = (state) => state === "running" ? '<span class="spinner"></span>' : '<span class="st ' + state + '">' + (ICONS[state] || "") + "</span>";
const STATE_TEXT = { ok: "passed", failed: "failed", cancelled: "cancelled", running: "running", queued: "queued" };

function seconds(sec) {
  sec = Math.max(0, Math.round(sec));
  return sec < 60 ? sec + " s" : Math.floor(sec / 60) + " min " + String(sec % 60).padStart(2, "0") + " s";
}
function ago(t) {
  const sec = now() - t;
  if (sec < 45) return "just now";
  if (sec < 3600) return Math.round(sec / 60) + " min ago";
  if (sec < 86400) return Math.round(sec / 3600) + " h ago";
  return new Date(t * 1000).toLocaleDateString();
}
const duration = (job) => job.started ? seconds((job.finished || now()) - job.started) : "";

// ---- navigation + web tools

function renderNav() {
  const running = jobs.filter((j) => j.state === "running").length;
  const svc = services.map((s, i) => {
    const activeTab = s.id === tab;
    const state = s.up ? (s.managed ? "started by the hub" : "already running – not managed here") : (s.exit_code !== undefined ? "stopped (exit " + s.exit_code + ")" : "not running");
    let html = '<a class="nav-item' + (activeTab ? " active" : "") + '" data-tab="' + s.id + '" title="' + esc(s.description) + " (" + (i + 3) + ')">' +
      '<span class="icon"><span class="dot' + (s.up ? " up" : "") + '"></span></span>' + esc(s.label) + '<span class="sub">:' + s.port + "</span></a>";
    if (activeTab || !s.up) {
      html += '<div class="svc-state">' + state + "</div>";
      html += '<div class="svc-tools">' + (s.up
        ? '<a class="btn ghost sm" href="' + toolUrl(s) + '" target="_blank" rel="noopener">↗ New tab</a>' +
          (s.managed ? '<button class="btn ghost sm" data-service="' + s.id + '" data-action="restart">↻ Restart</button>' +
            '<button class="btn ghost sm" data-service="' + s.id + '" data-action="stop">■ Stop</button>' : "")
        : '<button class="btn sm" data-service="' + s.id + '" data-action="start">▶ Start</button>') + "</div>";
    }
    return html;
  }).join("");
  const working = chats.filter((c) => c.state === "working").length;
  const asking = chats.filter((c) => c.state === "asking").length;
  $("#nav").innerHTML =
    '<a class="nav-item' + (tab === "home" ? " active" : "") + '" data-tab="home" title="Commands (1)"><span class="icon">⌘</span>Commands' +
    (running ? '<span class="badge"><span class="spinner"></span>' + running + "</span>" : "") + "</a>" +
    '<a class="nav-item' + (tab === "chat" ? " active" : "") + '" data-tab="chat" title="Claude Code chat (2)"><span class="icon">✦</span>Claude' +
    (asking ? '<span class="badge asking">needs you</span>' : working ? '<span class="badge"><span class="spinner"></span>working</span>' : "") + "</a>" +
    '<div class="nav-label eyebrow">Web tools</div>' + svc;
}

function frameFor(service) {
  let box = document.getElementById("frame-" + service.id);
  if (!box) {
    box = document.createElement("div");
    box.id = "frame-" + service.id;
    box.className = "frame";
    box.hidden = true;
    $("#frames").appendChild(box);
  }
  const hasFrame = box.querySelector("iframe");
  if (service.up && !hasFrame) {
    box.innerHTML = '<iframe src="' + toolUrl(service) + '" title="' + esc(service.label) + '"></iframe>';
  } else if (!service.up && (hasFrame || !box.innerHTML)) {
    box.innerHTML = '<div class="down"><h1>' + esc(service.label) + " is not running</h1><p>" + esc(service.description) +
      '</p><p><button type="button" class="btn primary" data-service="' + service.id + '" data-action="start">▶ Start ' + esc(service.label) +
      '</button></p><div class="eyebrow">Last log lines</div><pre class="log-tail">…</pre></div>';
    api("/api/services/" + service.id + "/log").then((d) => {
      const pre = box.querySelector(".log-tail");
      if (pre) pre.textContent = d.log || "(no log yet)";
    }).catch(() => {});
  }
  return box;
}

function showTab(name) {
  tab = name === "chat" || services.some((s) => s.id === name) ? name : "home";
  history.replaceState(null, "", tab === "home" ? location.pathname : "#" + tab);
  $("#home").hidden = tab !== "home";
  $("#chat").hidden = tab !== "chat";
  if (tab === "chat") setTimeout(() => $("#chat-input").focus(), 0);
  services.forEach((s) => { frameFor(s).hidden = s.id !== tab; });
  renderNav();
}

async function loadServices() {
  try {
    services = await api("/api/services");
  } catch (err) {
    services = services.map((s) => Object.assign({}, s, { up: false }));
  }
  services.forEach((s) => frameFor(s));
  renderNav();
}

// ---- command tiles

function field(cmd, p) {
  const saved = (savedParams[cmd.id] || {})[p.name];
  const value = saved !== undefined ? saved : p.default;
  const attr = 'data-param="' + p.name + '"';
  if (p.type === "bool") return '<label class="field check"><input type="checkbox" ' + attr + (value ? " checked" : "") + ">" + esc(p.label) + "</label>";
  let input;
  if (p.type === "choice") {
    input = "<select " + attr + ">" + p.choices.map((c) => '<option value="' + esc(c) + '"' + (c === value ? " selected" : "") + ">" + esc(c || "default") + "</option>").join("") + "</select>";
  } else if (p.type === "int") {
    input = '<input type="number" ' + attr + ' min="' + p.min + '" max="' + p.max + '" value="' + esc(value) + '"' + (p.optional ? ' placeholder="optional"' : "") + ">";
  } else {
    input = '<input type="text" ' + attr + ' value="' + esc(value) + '" placeholder="' + esc(p.placeholder || "") + '" pattern="' + esc(p.pattern) + '">';
  }
  return '<label class="field' + (p.type === "text" ? " wide" : "") + '"><span>' + esc(p.label) + "</span>" + input + "</label>";
}

function renderCommands() {
  const groups = [];
  commands.forEach((c) => { if (!groups.includes(c.group)) groups.push(c.group); });
  $("#commands").innerHTML = groups.map((g) => {
    const meta = GROUPS[g] || { color: "var(--text-2)", text: "" };
    return '<section class="group" data-group="' + esc(g) + '" style="--c: ' + meta.color + '"><div class="group-head"><h2>' + esc(g) + "</h2><p>" + esc(meta.text) + '</p></div><div class="tiles">' +
      commands.filter((c) => c.group === g).map((c) =>
        '<form class="tile" data-command="' + c.id + '" data-search="' + esc((c.label + " " + c.description + " " + c.script).toLowerCase()) + '">' +
        '<div class="tile-head"><div><div class="tile-title">' + esc(c.label) + '</div><div class="tile-desc">' + esc(c.description) + "</div></div>" +
        '<button type="submit" class="btn run">▶ Run</button></div>' +
        (c.params.length ? '<div class="fields">' + c.params.map((p) => field(c, p)).join("") + "</div>" : "") +
        '<div class="tile-foot"><code class="script" title="' + esc(c.script) + '">' + esc(c.script) + '</code><span class="last" data-last="' + c.id + '"></span></div>' +
        "</form>").join("") + "</div></section>";
  }).join("");
}

function renderTileStates() {
  document.querySelectorAll("form.tile").forEach((form) => {
    const job = jobs.find((j) => j.command === form.dataset.command); // jobs are newest first
    form.classList.toggle("busy", !!job && active(job));
    const last = form.querySelector(".last");
    if (!job) { last.innerHTML = '<span class="muted">never run</span>'; last.removeAttribute("data-job"); return; }
    last.dataset.job = job.id;
    last.innerHTML = statusIcon(job.state) + (active(job) ? STATE_TEXT[job.state] + (job.started ? " · " + duration(job) : "") : STATE_TEXT[job.state] + " " + ago(job.finished || job.created));
  });
}

function readParams(form, cmd) {
  const params = {};
  cmd.params.forEach((p) => {
    const el = form.querySelector('[data-param="' + p.name + '"]');
    if (p.type === "bool") params[p.name] = el.checked;
    else if (p.type === "int") params[p.name] = el.value === "" ? "" : Number(el.value);
    else params[p.name] = el.value;
  });
  return params;
}

async function run(commandId, params) {
  try {
    const job = await api("/api/jobs", { command: commandId, params });
    savedParams[commandId] = params;
    localStorage.setItem(PARAMS_STORE, JSON.stringify(savedParams));
    await loadJobs();
    selectJob(job.id);
  } catch (err) {
    toast("Cannot run: " + err.message, "var(--bad)");
  }
}

// ---- activity

function paramsText(job) {
  return Object.entries(job.params).filter(([, v]) => v !== "" && v !== false).map(([k, v]) => (v === true ? k : k + "=" + v)).join("  ");
}

function renderJobs() {
  $("#jobs").innerHTML = jobs.map((j) =>
    '<li data-job="' + j.id + '" class="' + (selectedJob && selectedJob.id === j.id ? "selected" : "") + '">' + statusIcon(j.state) +
    '<span class="name">' + esc(j.label) + '</span><span class="params">' + esc(paramsText(j)) + '</span><span class="time">' +
    (active(j) ? duration(j) || "queued" : ago(j.finished || j.created) + " · " + duration(j)) + "</span></li>").join("");
  $("#job-empty").hidden = jobs.length > 0;
  const running = jobs.filter((j) => j.state === "running").length;
  const queued = jobs.filter((j) => j.state === "queued").length;
  $("#running").textContent = running ? running + " running" + (queued ? ", " + queued + " queued" : "") : "";
  const current = jobs.find((j) => j.state === "running");
  document.title = (current ? "● " + current.label + " – " : "") + "Devtools – Eastern Flank";
}

function notifyFinished() {
  const states = {};
  jobs.forEach((j) => { states[j.id] = j.state; });
  if (lastStates) {
    jobs.forEach((j) => {
      const before = lastStates[j.id];
      if (before && (before === "running" || before === "queued") && !active(j) && j.state !== "cancelled") {
        const ok = j.state === "ok";
        toast((ok ? "✓ " : "✕ ") + j.label + " " + (ok ? "passed" : "failed (exit " + j.exit_code + ")") + " · " + duration(j), ok ? "var(--ok)" : "var(--bad)", j.id);
      }
    });
  }
  lastStates = states;
}

async function loadJobs() {
  try {
    jobs = await api("/api/jobs");
  } catch (err) {
    return; // hub stopped; the next poll retries
  }
  notifyFinished();
  renderJobs();
  renderTileStates();
  renderNav();
}

function classify(line) {
  if (/\b(ERROR|FAILED|FAIL|Error|Traceback|SCRIPT ERROR|failed)\b/.test(line) && !/\b0 failed\b/.test(line)) return "e";
  if (/\bWARNING\b|\bwarning:/.test(line)) return "w";
  if (/\b(OK|passed|0 failed)\b|^== OK ==/.test(line)) return "o";
  return "";
}

function appendLines(lines) {
  const log = $("#job-log");
  const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 40;
  const placeholder = log.querySelector(".placeholder");
  if (placeholder && lines.length) placeholder.remove();
  const frag = document.createDocumentFragment();
  for (const line of lines) {
    const div = document.createElement("div");
    const cls = classify(line);
    if (cls) {
      div.className = cls;
      selectedJob.counts[cls] = (selectedJob.counts[cls] || 0) + 1;
    }
    div.textContent = line || " ";
    frag.appendChild(div);
  }
  log.appendChild(frag);
  if (atBottom) log.scrollTop = log.scrollHeight;
  const c = selectedJob.counts;
  $("#log-counts").innerHTML = (c.e ? '<span class="e">' + c.e + " error" + (c.e > 1 ? "s" : "") + "</span>" : "") +
    (c.w ? '<span class="w">' + c.w + " warning" + (c.w > 1 ? "s" : "") + "</span>" : "");
}

function selectJob(id) {
  selectedJob = { id, next: 0, state: null, counts: {} };
  $("#job").hidden = false;
  $("#job-log").innerHTML = '<div class="placeholder">Waiting for output…</div>';
  $("#job-images").innerHTML = "";
  $("#log-counts").innerHTML = "";
  renderJobs();
  pollJob();
}

async function pollJob() {
  const sel = selectedJob;
  if (!sel) return;
  let job;
  try {
    job = await api("/api/jobs/" + sel.id + "?since=" + sel.next);
  } catch (err) {
    return;
  }
  if (selectedJob !== sel) return;
  appendLines(job.lines);
  sel.next = job.next;
  sel.command = job.command;
  sel.params = job.params;
  $("#job-title").innerHTML = esc(job.label) + ' <span class="pill ' + job.state + '">' + (job.state === "running" ? '<span class="spinner"></span>' : "") +
    STATE_TEXT[job.state] + (job.state === "failed" ? " · exit " + job.exit_code : "") + "</span>";
  const params = paramsText(job);
  $("#job-meta").textContent = (job.started ? "started " + new Date(job.started * 1000).toLocaleTimeString() + " · " + duration(job) : "waiting for the running job to finish") +
    (params ? " · " + params : "");
  $("#job-argv").textContent = job.argv.join(" ");
  $("#job-cancel").hidden = !active(job);
  if (sel.state !== job.state) {
    sel.state = job.state;
    const images = $("#job-images");
    images.classList.toggle("single", job.images.length === 1);
    images.innerHTML = job.images.map((path) => {
      const src = "/files/" + esc(path) + "?t=" + job.finished;
      return '<figure><a href="' + src + '" target="_blank" title="Open full size"><img src="' + src + '" alt=""></a><figcaption>' + esc(path) + "</figcaption></figure>";
    }).join("");
    if (!active(job) && !job.lines.length && sel.next === 0) $("#job-log").innerHTML = '<div class="placeholder">No output.</div>';
  }
  if (active(job)) setTimeout(pollJob, 600);
}

// ---- Claude chat (tools/devtools/chat.py)

const CHAT_STATE = { working: "working", asking: "needs you", idle: "waiting for you", stopped: "stopped", failed: "failed" };
const chatPill = (state) => '<span class="pill chat-' + state + '">' + (state === "working" ? '<span class="spinner"></span>' : "") + CHAT_STATE[state] + "</span>";
const money = (usd) => (typeof usd === "number" ? "$" + usd.toFixed(2) : "");
const WINDOW_LABELS = { five_hour: "5-hour limit", seven_day: "Weekly limit", seven_day_opus: "Weekly · Opus", seven_day_sonnet: "Weekly · Sonnet" };
const tokens = (n) => (n >= 1e6 ? (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + "M" : n >= 1000 ? Math.round(n / 1000) + "k" : String(n));
const IDLE_HINT = "Message Claude…  (Enter sends, Shift+Enter new line, / for commands)";

function backlogFrame() {
  const box = document.getElementById("frame-backlog");
  const frame = box && box.querySelector("iframe");
  const svc = services.find((s) => s.id === "backlog");
  return frame && svc ? { win: frame.contentWindow, origin: new URL(toolUrl(svc)).origin } : null;
}

function tellBacklog() {
  const target = backlogFrame();
  if (!target) return;
  const tasks = {};
  chats.slice().reverse().forEach((c) => { if (c.task) tasks[c.task] = c.state; });
  target.win.postMessage({ type: "devtools:chats", available: chatInfo.available, tasks }, target.origin);
}

function notifyAsking(before) {
  chats.forEach((c) => {
    const was = before.find((b) => b.id === c.id);
    if (c.state === "asking" && (!was || was.state !== "asking")) toast("✦ " + c.title + " – Claude needs you", "var(--accent)", null, c.id);
  });
}

async function loadChats() {
  let data;
  try { data = await api("/api/chat"); } catch (err) { return; }
  const before = chats;
  chats = data.sessions;
  chatInfo = data;
  notifyAsking(before);
  renderUsage();
  renderChatList();
  renderNav();
  tellBacklog();
  const asking = chats.filter((c) => c.state === "asking").length;
  if (asking) document.title = "● Claude needs you – Devtools";
  else if (document.title.startsWith("● Claude")) document.title = "Devtools – Eastern Flank";
}

function resetText(t) {
  if (!t) return "";
  const d = new Date(t * 1000);
  const sameDay = d.toDateString() === new Date().toDateString();
  return "resets " + (sameDay ? "" : d.toLocaleDateString(undefined, { weekday: "short" }) + " ") + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function renderUsage() {
  const limits = chatInfo.limits;
  const box = $("#usage");
  if (!limits || !Object.keys(limits.windows || {}).length) {
    box.innerHTML = '<span class="eyebrow">Claude usage</span><span class="muted">Shows up once a Claude chat talks to the API.</span>';
    return;
  }
  const working = chats.some((c) => c.state === "working");
  const bars = Object.entries(limits.windows).map(([name, w]) => {
    const pct = Math.round(w.utilization * 100);
    const level = pct >= 90 ? "bad" : pct >= 70 ? "warn" : "ok";
    return '<div class="u-row"><div class="u-label"><span>' + esc(WINDOW_LABELS[name] || name.replace(/_/g, " ")) + "</span><b>" + pct + "%</b></div>" +
      '<div class="u-bar"><i class="' + level + '" style="width: ' + Math.min(100, pct) + '%"></i></div><div class="u-reset">' + esc(resetText(w.resets_at)) + "</div></div>";
  }).join("");
  const limited = limits.status && limits.status !== "allowed" && limits.status !== "allowed_warning";
  box.innerHTML = '<span class="eyebrow">Claude usage</span>' + bars +
    (limited ? '<div class="u-alert">Limit reached (' + esc(limits.status) + ")</div>" : "") +
    '<div class="u-reset">' + (working ? "live" : "as of " + ago(limits.updated)) + "</div>";
}

function renderChatList() {
  $("#chat-sessions").innerHTML = chats.map((c) =>
    '<li data-chat="' + esc(c.id) + '" class="' + (selectedChat && selectedChat.id === c.id ? "selected" : "") + '">' +
    '<span class="chat-dot ' + c.state + '"></span><span class="name">' + esc(c.title) + '</span><span class="time">' +
    (c.state === "working" || c.state === "asking" ? CHAT_STATE[c.state] : ago(c.updated)) + (c.cost_usd ? " · " + money(c.cost_usd) : "") + "</span></li>").join("") ||
    '<li class="muted empty-li">No chats yet.</li>';
  if (!selectedChat) renderChatHead(null);
}

function mdLite(text) {
  // fenced code blocks, inline code, bold, headings – the rest stays plain (pre-wrap)
  return text.split(/```[^\n]*\n?/).map((part, i) => {
    if (i % 2) return "<pre>" + esc(part.replace(/\n$/, "")) + "</pre>";
    return esc(part).replace(/`([^`\n]+)`/g, "<code>$1</code>").replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
      .replace(/^#{1,4} (.*)$/gm, "<b class=\"h\">$1</b>");
  }).join("");
}

function diffHtml(oldText, newText) {
  const del = String(oldText || "").split("\n").map((l) => '<span class="del">- ' + esc(l) + "</span>");
  const add = String(newText || "").split("\n").map((l) => '<span class="add">+ ' + esc(l) + "</span>");
  return '<pre class="diff">' + del.concat(add).join("\n") + "</pre>";
}

function toolInput(name, input) {
  // what the IDE shows for a tool call: diffs for edits, the command for Bash, the list for todos
  if (!input || typeof input !== "object") return "";
  if (name === "Edit") return '<div class="path">' + esc(input.file_path || "") + (input.replace_all ? " (all occurrences)" : "") + "</div>" + diffHtml(input.old_string, input.new_string);
  if (name === "MultiEdit") return '<div class="path">' + esc(input.file_path || "") + "</div>" + (input.edits || []).map((e) => diffHtml(e.old_string, e.new_string)).join("");
  if (name === "Write") return '<div class="path">' + esc(input.file_path || "") + '</div><pre class="diff">' + String(input.content || "").split("\n").map((l) => '<span class="add">+ ' + esc(l) + "</span>").join("\n") + "</pre>";
  if (name === "Bash") return '<pre class="cmd">$ ' + esc(input.command || "") + "</pre>" + (input.description ? '<div class="muted">' + esc(input.description) + "</div>" : "");
  if (name === "TodoWrite") return '<ul class="todos">' + (input.todos || []).map((t) => '<li class="' + esc(t.status) + '">' + ({ completed: "☑", in_progress: "◐" }[t.status] || "☐") + " " + esc(t.content) + "</li>").join("") + "</ul>";
  if (name === "Agent" || name === "Task") return '<div class="muted">' + esc((input.subagent_type || "agent") + (input.model ? " · " + input.model : "")) + "</div><pre>" + esc(input.prompt || "") + "</pre>";
  return "<pre>" + esc(JSON.stringify(input, null, 2)) + "</pre>";
}

function askCard(e, pending) {
  const div = document.createElement("div");
  div.className = "m ask" + (pending ? " open" : "");
  div.dataset.request = e.request_id;
  if (e.tool === "AskUserQuestion") {
    const qs = (e.input && e.input.questions) || [];
    div.innerHTML = '<div class="ask-title">✦ Claude asks</div>' + qs.map((q, qi) =>
      '<fieldset class="q" data-question="' + esc(q.question) + '" data-multi="' + (q.multiSelect ? 1 : 0) + '"><legend>' + esc(q.question) + "</legend>" +
      (q.options || []).map((o) => '<label class="opt"><input type="' + (q.multiSelect ? "checkbox" : "radio") + '" name="q' + qi + '" value="' + esc(o.label) + '"' + (pending ? "" : " disabled") + '><span><b>' +
        esc(o.label) + "</b>" + (o.description ? "<small>" + esc(o.description) + "</small>" : "") + "</span></label>").join("") +
      '<input type="text" class="other" placeholder="Other…"' + (pending ? "" : " disabled") + "></fieldset>").join("") +
      (pending ? '<div class="ask-actions"><button type="button" class="btn primary sm" data-answer="submit">Submit</button><button type="button" class="btn ghost sm" data-answer="deny">Skip</button></div>' : '<div class="ask-done muted">answered</div>');
  } else {
    div.innerHTML = '<div class="ask-title">✦ Allow ' + esc(e.tool) + "?</div>" + toolInput(e.tool, e.input) +
      (pending ? '<div class="ask-actions"><button type="button" class="btn primary sm" data-answer="allow">Allow</button>' +
        (e.always ? '<button type="button" class="btn sm" data-answer="always" title="Allow and add the suggested permission rule to your local settings">Always allow</button>' : "") +
        '<input type="text" class="deny-note" placeholder="Why not / what instead (optional)"><button type="button" class="btn danger sm" data-answer="deny">Deny</button></div>' : '<div class="ask-done muted">answered</div>');
  }
  return div;
}

function chatEntry(e, c) {
  const pending = (c.pending_requests || []).some((p) => p.request_id === e.request_id);
  if (e.kind === "ask") return askCard(e, pending);
  const div = document.createElement("div");
  div.className = "m " + e.kind + (e.sub ? " sub" : "");
  if (e.kind === "user") div.innerHTML = '<div class="bubble">' + mdLite(e.text) + "</div>";
  else if (e.kind === "text") div.innerHTML = (e.sub ? '<span class="who">subagent</span>' : "") + mdLite(e.text);
  else if (e.kind === "tool") {
    div.innerHTML = '<details' + (e.name === "TodoWrite" ? " open" : "") + '><summary>› ' + esc(e.text) + '</summary><div class="tool-body">' + toolInput(e.name, e.input) + "</div></details>";
    if (e.id) div.dataset.tool = e.id;
  } else if (e.kind === "tool_result") {
    const tool = $("#chat-log").querySelector('[data-tool="' + CSS.escape(e.tool_use_id || "") + '"]');
    const body = '<pre class="result' + (e.is_error ? " err" : "") + '">' + esc(e.text || "(no output)") + "</pre>";
    if (tool) {
      tool.querySelector(".tool-body").insertAdjacentHTML("beforeend", body);
      if (e.is_error) tool.classList.add("failed");
      return null;
    }
    div.innerHTML = body;
  } else if (e.kind === "answered") {
    const card = $("#chat-log").querySelector('[data-request="' + CSS.escape(e.request_id) + '"]');
    const text = e.answers ? Object.values(e.answers).join(" · ") : { allow: "allowed", always: "always allowed", deny: "denied" + (e.text ? ": " + e.text : "") }[e.behavior];
    if (card) {
      card.classList.remove("open");
      card.querySelectorAll(".ask-actions").forEach((a) => a.remove());
      card.querySelectorAll("input").forEach((i) => { i.disabled = true; });
      card.insertAdjacentHTML("beforeend", '<div class="ask-done ' + (e.behavior === "deny" ? "no" : "yes") + '">' + esc(text) + "</div>");
      card.querySelectorAll(".ask-done.muted").forEach((d) => d.remove());
    }
    return null;
  } else if (e.kind === "turn") {
    div.className += e.is_error ? " error" : "";
    div.innerHTML = "<span>" + (e.is_error ? "turn stopped" + (e.text ? ": " + esc(e.text) : "") : "turn finished") + (e.cost_usd ? " · " + money(e.cost_usd) + " so far" : "") + "</span>";
  } else div.textContent = e.text;
  return div;
}

function renderChatHead(c) {
  if (!c) {
    $("#chat-head").innerHTML = '<div><div class="job-title">New chat</div><div class="job-meta">' +
      (chatInfo.available ? "A Claude Code session in the repository – like the one in your editor. To implement a task, open it in the Backlog and press ▶ Implement." : esc(chatInfo.hint)) + "</div></div>";
    return;
  }
  const context = c.context_tokens ? "context " + tokens(c.context_tokens) + (c.context_window ? " / " + tokens(c.context_window) + " (" + Math.round(100 * c.context_tokens / c.context_window) + "%)" : "") : "";
  const meta = [c.task ? "/implement-task " + c.task : "free chat", c.cost_usd ? money(c.cost_usd) : "", context, c.error].filter(Boolean).map(esc).join(" · ");
  $("#chat-head").innerHTML = '<div class="chat-title-box"><div class="job-title">' + esc(c.title) + " " + chatPill(c.state) + '</div><div class="job-meta">' + meta + "</div></div>" +
    '<div class="job-actions">' +
    (c.session_id ? '<button type="button" class="btn ghost sm" id="chat-copy" title="Continue this session in a terminal (run it in the repository folder)">⧉ claude --resume</button>' : "") +
    (c.state === "working" || c.state === "asking" ? '<button type="button" class="btn danger sm" id="chat-stop" title="Interrupt the turn (like Esc) – the session stays">■ Stop</button>' : "") + "</div>";
}

function renderChatBody(c, fresh) {
  const log = $("#chat-log");
  const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 60;
  if (fresh) log.innerHTML = "";
  log.querySelectorAll(".thinking").forEach((t) => t.remove());
  c.log.forEach((e) => { const el = chatEntry(e, c); if (el) log.appendChild(el); });
  // cards whose request expired (turn interrupted, process gone) can't be answered any more
  log.querySelectorAll(".ask.open").forEach((card) => {
    if (!(c.pending_requests || []).some((p) => p.request_id === card.dataset.request)) {
      card.classList.remove("open");
      card.querySelectorAll(".ask-actions").forEach((a) => a.remove());
      card.querySelectorAll("input").forEach((i) => { i.disabled = true; });
    }
  });
  if (c.state === "working") {
    const thinking = document.createElement("div");
    thinking.className = "m thinking";
    thinking.innerHTML = '<span class="spinner"></span> Claude is working…';
    log.appendChild(thinking);
  }
  if (atBottom || fresh || (c.state === "asking" && c.log.length)) log.scrollTop = log.scrollHeight;
  const files = $("#chat-files");
  files.hidden = !c.changed_files.length;
  files.querySelector("summary").textContent = c.changed_files.length + " changed file" + (c.changed_files.length === 1 ? "" : "s") + " in the working tree (git status)";
  files.querySelector("pre").textContent = c.changed_files.join("\n");
  $("#chat-send").disabled = !chatInfo.available;
  $("#chat-input").placeholder = c.state === "working" ? "Claude is working – a message now is folded into the current turn…" : IDLE_HINT;
}

function selectChat(id) {
  if (selectedChat && selectedChat.timer) clearTimeout(selectedChat.timer);
  selectedChat = id ? { id, next: 0, timer: null } : null;
  renderChatList();
  if (!id) {
    $("#chat-log").innerHTML = '<div class="empty">' + (chatInfo.available ? "Ask anything – Claude works in this repository, with the same settings as in your editor." : esc(chatInfo.hint)) + "</div>";
    $("#chat-files").hidden = true;
    $("#chat-send").disabled = !chatInfo.available;
    $("#chat-input").focus();
    return;
  }
  pollChat(true);
}

async function pollChat(fresh) {
  const sel = selectedChat;
  if (!sel) return;
  let c;
  try { c = await api("/api/chat/" + encodeURIComponent(sel.id) + "?since=" + (fresh ? 0 : sel.next)); } catch (err) { return; }
  if (selectedChat !== sel) return;
  sel.next = c.log_from + c.log.length;
  renderChatHead(c);
  renderChatBody(c, fresh);
  sel.timer = setTimeout(() => pollChat(false), c.state === "working" ? 700 : 2000);
}

function refreshChat() {
  if (!selectedChat) return;
  if (selectedChat.timer) clearTimeout(selectedChat.timer);
  pollChat(false);
}

async function sendChat() {
  const input = $("#chat-input");
  const text = input.value.trim();
  if (!text || $("#chat-send").disabled) return;
  $("#chat-send").disabled = true;
  hideCommands();
  try {
    if (selectedChat) {
      await api("/api/chat/" + encodeURIComponent(selectedChat.id) + "/send", { text });
    } else {
      const c = await api("/api/chat", { text });
      selectedChat = { id: c.id, next: 0, timer: null };
    }
    input.value = "";
    await loadChats();
    selectChat(selectedChat.id);
  } catch (err) {
    toast("Cannot send: " + err.message, "var(--bad)");
  }
  $("#chat-send").disabled = !chatInfo.available;
}

async function answerRequest(card, kind) {
  const body = { request_id: card.dataset.request };
  if (kind === "submit") {
    const answers = {};
    let missing = false;
    card.querySelectorAll("fieldset.q").forEach((q) => {
      const picked = [...q.querySelectorAll("input:checked")].map((i) => i.value);
      const other = q.querySelector(".other").value.trim();
      if (other) picked.push(other);
      if (!picked.length) missing = true;
      answers[q.dataset.question] = picked.join(", ");
    });
    if (missing) { toast("Answer every question", "var(--warn)"); return; }
    Object.assign(body, { behavior: "allow", answers });
  } else {
    body.behavior = kind;
    const note = card.querySelector(".deny-note");
    if (kind === "deny" && note) body.message = note.value;
  }
  card.querySelectorAll("button").forEach((b) => { b.disabled = true; });
  try {
    await api("/api/chat/" + encodeURIComponent(selectedChat.id) + "/answer", body);
  } catch (err) {
    toast("Cannot answer: " + err.message, "var(--bad)");
    card.querySelectorAll("button").forEach((b) => { b.disabled = false; });
  }
  await loadChats();
  refreshChat();
}

// ---- slash command suggestions (the session's commands, from the CLI's initialize answer)

let commandPick = 0;
function hideCommands() { $("#chat-commands").hidden = true; }
function showCommands() {
  const value = $("#chat-input").value;
  const box = $("#chat-commands");
  const m = /^\/(\S*)$/.exec(value);
  const list = m ? (chatInfo.commands || []).filter((c) => c.name.startsWith(m[1])).slice(0, 12) : [];
  if (!list.length) { hideCommands(); return; }
  commandPick = Math.min(commandPick, list.length - 1);
  box.innerHTML = list.map((c, i) => '<li data-command-name="' + esc(c.name) + '" class="' + (i === commandPick ? "on" : "") + '"><b>/' + esc(c.name) + "</b>" +
    (c.hint ? ' <span class="hint">' + esc(c.hint) + "</span>" : "") + "<small>" + esc(c.description) + "</small></li>").join("");
  box.hidden = false;
}
function pickCommand(name) {
  $("#chat-input").value = "/" + name + " ";
  hideCommands();
  $("#chat-input").focus();
}

window.addEventListener("message", (ev) => {
  const target = backlogFrame();
  if (!target || ev.origin !== target.origin || ev.source !== target.win || !ev.data) return;
  if (ev.data.type === "devtools:hello") tellBacklog();
  else if ((ev.data.type === "devtools:implement" || ev.data.type === "devtools:open-chat") && /^TASK-\d+[a-z]?$/.test(ev.data.task)) {
    if (ev.data.type === "devtools:implement") implementTask(ev.data.task);
    else { const c = chats.find((x) => x.task === ev.data.task); showTab("chat"); if (c) selectChat(c.id); }
  }
});

async function implementTask(task) {
  showTab("chat");
  const existing = chats.find((c) => c.task === task);
  if (existing) { selectChat(existing.id); return; }
  if (!confirm("Start /implement-task " + task + " in a Claude Code session?\n\nIt runs with your subscription and edits the working tree; it commits only when you ask.")) return;
  try {
    const c = await api("/api/chat", { task });
    await loadChats();
    selectChat(c.id);
  } catch (err) {
    toast("Cannot start " + task + ": " + err.message, "var(--bad)");
  }
}

$("#chat-form").addEventListener("submit", (ev) => { ev.preventDefault(); sendChat(); });
$("#chat-input").addEventListener("input", () => { commandPick = 0; showCommands(); });
$("#chat-input").addEventListener("keydown", (ev) => {
  const box = $("#chat-commands");
  if (!box.hidden) {
    const items = box.querySelectorAll("li");
    if (ev.key === "ArrowDown" || ev.key === "ArrowUp") {
      ev.preventDefault();
      commandPick = (commandPick + (ev.key === "ArrowDown" ? 1 : items.length - 1)) % items.length;
      showCommands();
      return;
    }
    if (ev.key === "Tab" || (ev.key === "Enter" && !ev.shiftKey)) {
      ev.preventDefault();
      pickCommand(items[commandPick].dataset.commandName);
      return;
    }
    if (ev.key === "Escape") { hideCommands(); return; }
  }
  if (ev.key === "Escape" && selectedChat) { ev.preventDefault(); stopChat(); return; }
  if (ev.key === "Enter" && !ev.shiftKey && !ev.isComposing) { ev.preventDefault(); sendChat(); }
});
$("#chat-commands").addEventListener("mousedown", (ev) => {
  const li = ev.target.closest("[data-command-name]");
  if (li) { ev.preventDefault(); pickCommand(li.dataset.commandName); }
});
$("#chat-new").addEventListener("click", () => selectChat(null));
$("#chat-steps").addEventListener("change", (ev) => $("#chat-log").classList.toggle("no-steps", !ev.target.checked));
$("#chat-sessions").addEventListener("click", (ev) => {
  const li = ev.target.closest("[data-chat]");
  if (li) selectChat(li.dataset.chat);
});
$("#chat-log").addEventListener("click", (ev) => {
  const button = ev.target.closest("[data-answer]");
  if (button && selectedChat) answerRequest(button.closest("[data-request]"), button.dataset.answer);
});

async function stopChat() {
  const c = chats.find((x) => x.id === selectedChat.id);
  if (!c || (c.state !== "working" && c.state !== "asking")) return;
  try { await api("/api/chat/" + encodeURIComponent(selectedChat.id) + "/stop", {}); } catch (err) { toast(err.message, "var(--bad)"); }
  await loadChats();
  refreshChat();
}

$("#chat-head").addEventListener("click", async (ev) => {
  if (!selectedChat) return;
  if (ev.target.closest("#chat-stop")) stopChat();
  else if (ev.target.closest("#chat-copy")) {
    const c = chats.find((x) => x.id === selectedChat.id);
    if (c) navigator.clipboard.writeText("claude --resume " + c.session_id).then(() => toast("Copied – run it in the repository folder", "var(--ok)"));
  }
});

// ---- toasts

function toast(text, color, jobId, chatId) {
  const el = document.createElement("div");
  el.className = "toast";
  el.style.setProperty("--c", color || "var(--text-2)");
  el.textContent = text;
  el.addEventListener("click", () => {
    if (jobId) { showTab("home"); selectJob(jobId); }
    if (chatId) { showTab("chat"); selectChat(chatId); }
    el.remove();
  });
  $("#toasts").appendChild(el);
  setTimeout(() => el.remove(), 7000);
}

// ---- events

document.addEventListener("click", async (ev) => {
  const tabLink = ev.target.closest("[data-tab]");
  if (tabLink) { ev.preventDefault(); showTab(tabLink.dataset.tab); return; }
  const action = ev.target.closest("[data-action]");
  if (action) {
    action.disabled = true;
    try { await api("/api/services/" + action.dataset.service + "/" + action.dataset.action, {}); } catch (err) { toast(err.message, "var(--bad)"); }
    const box = document.getElementById("frame-" + action.dataset.service);
    if (box && action.dataset.action === "restart") box.innerHTML = "";
    await loadServices();
    showTab(tab);
    return;
  }
  const item = ev.target.closest("[data-job]");
  if (item && item.dataset.job && !ev.target.closest("#chat")) selectJob(item.dataset.job);
});

document.addEventListener("submit", (ev) => {
  const form = ev.target.closest("form.tile");
  if (!form) return;
  ev.preventDefault();
  const cmd = commands.find((c) => c.id === form.dataset.command);
  run(cmd.id, readParams(form, cmd));
});

document.addEventListener("keydown", (ev) => {
  if (ev.target.closest("input, select, textarea") || ev.ctrlKey || ev.metaKey || ev.altKey) return;
  const pages = ["home", "chat"].concat(services.map((s) => s.id));
  const index = Number(ev.key) - 1;
  if (index >= 0 && index < pages.length) showTab(pages[index]);
});

$("#find").addEventListener("input", (ev) => {
  const q = ev.target.value.toLowerCase().trim();
  document.querySelectorAll("form.tile").forEach((f) => { f.hidden = !!q && !f.dataset.search.includes(q); });
  document.querySelectorAll(".group").forEach((g) => { g.hidden = !g.querySelector("form.tile:not([hidden])"); });
});
$("#job-cancel").addEventListener("click", () => selectedJob && api("/api/jobs/" + selectedJob.id + "/cancel", {}).then(loadJobs));
$("#job-rerun").addEventListener("click", () => selectedJob && selectedJob.command && run(selectedJob.command, selectedJob.params));
$("#log-problems").addEventListener("change", (ev) => $("#job-log").classList.toggle("problems", ev.target.checked));
$("#log-copy").addEventListener("click", () => {
  const text = [...$("#job-log").children].filter((d) => !d.classList.contains("placeholder")).map((d) => d.textContent).join("\n");
  navigator.clipboard.writeText(text).then(() => toast("Output copied", "var(--ok)"), () => toast("Copy failed", "var(--bad)"));
});

(async () => {
  [commands] = await Promise.all([api("/api/commands"), loadServices(), loadChats()]);
  renderCommands();
  await loadJobs();
  showTab(location.hash.slice(1) || "home");
  if (jobs.length) selectJob(jobs[0].id);
  selectChat(chats.length ? chats[0].id : null);
  setInterval(loadServices, 3000);
  setInterval(loadJobs, 1500);
  setInterval(loadChats, 2000);
})();
