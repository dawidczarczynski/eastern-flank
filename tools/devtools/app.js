"use strict";
// Devtools hub: web tools as tabs (iframes), command-line tools as jobs with live output.

const PARAMS_STORE = "devtools.params";
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
let selectedJob = null; // { id, next, state }
const savedParams = JSON.parse(localStorage.getItem(PARAMS_STORE) || "{}");

const toolUrl = (s) => location.protocol + "//" + location.hostname + ":" + s.port + "/";
const duration = (job) => {
  if (!job.started) return "";
  const sec = Math.round((job.finished || Date.now() / 1000) - job.started);
  return sec < 60 ? sec + " s" : Math.floor(sec / 60) + " min " + (sec % 60) + " s";
};

// ---- tabs + web tools

function renderTabs() {
  $("#tabs").innerHTML = '<a data-tab="home">Home</a>' + services.map((s) =>
    '<a data-tab="' + s.id + '"><span class="dot' + (s.up ? " up" : "") + '"></span>' + esc(s.label) + "</a>").join("");
  document.querySelectorAll("#tabs a").forEach((a) => a.classList.toggle("active", a.dataset.tab === tab));
}

function renderServices() {
  $("#services").innerHTML = services.map((s) => {
    const state = s.up ? (s.managed ? "started by the hub" : "already running") : (s.exit_code !== undefined ? "stopped (exit " + s.exit_code + ")" : "not running");
    return '<div class="card"><div class="head"><span class="dot' + (s.up ? " up" : "") + '"></span>' + esc(s.label) +
      '<span class="state">' + state + '</span></div><div class="desc">' + esc(s.description) + "</div>" +
      '<div class="actions"><button type="button" class="primary" data-open="' + s.id + '"' + (s.up ? "" : " disabled") + ">Open</button>" +
      '<a href="' + toolUrl(s) + '" target="_blank" rel="noopener">localhost:' + s.port + " ↗</a>" +
      (s.up ? (s.managed ? '<button type="button" data-service="' + s.id + '" data-action="restart">Restart</button>' +
        '<button type="button" data-service="' + s.id + '" data-action="stop">Stop</button>' : "")
        : '<button type="button" data-service="' + s.id + '" data-action="start">Start</button>') +
      "</div></div>";
  }).join("");
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
    box.innerHTML = '<iframe class="frame" src="' + toolUrl(service) + '" title="' + esc(service.label) + '"></iframe>';
  } else if (!service.up && (hasFrame || !box.innerHTML)) {
    box.innerHTML = '<div class="down"><h2>' + esc(service.label) + ' is not running</h2><p><button type="button" class="primary" data-service="' +
      service.id + '" data-action="start">Start</button></p><pre class="log">…</pre></div>';
    api("/api/services/" + service.id + "/log").then((d) => { const pre = box.querySelector(".log"); if (pre) pre.textContent = d.log || "(no log)"; }).catch(() => {});
  }
  return box;
}

function showTab(name) {
  tab = services.some((s) => s.id === name) ? name : "home";
  history.replaceState(null, "", tab === "home" ? location.pathname : "#" + tab);
  $("#home").hidden = tab !== "home";
  services.forEach((s) => { frameFor(s).hidden = s.id !== tab; });
  const service = services.find((s) => s.id === tab);
  $("#newtab").hidden = !service;
  if (service) $("#newtab").href = toolUrl(service);
  renderTabs();
}

async function loadServices() {
  try {
    services = await api("/api/services");
  } catch (err) {
    services = services.map((s) => Object.assign({}, s, { up: false }));
  }
  renderTabs();
  renderServices();
  services.forEach((s) => frameFor(s));
}

// ---- commands

function paramInput(cmd, p) {
  const saved = (savedParams[cmd.id] || {})[p.name];
  const value = saved !== undefined ? saved : p.default;
  const name = 'data-param="' + p.name + '"';
  let input;
  if (p.type === "bool") input = '<input type="checkbox" ' + name + (value ? " checked" : "") + ">";
  else if (p.type === "choice") input = "<select " + name + ">" + p.choices.map((c) => "<option" + (c === value ? " selected" : "") + ' value="' + esc(c) + '">' + esc(c || "–") + "</option>").join("") + "</select>";
  else if (p.type === "int") input = '<input type="number" ' + name + ' min="' + p.min + '" max="' + p.max + '" value="' + esc(value) + '"' + (p.optional ? ' placeholder="–"' : "") + ">";
  else input = '<input type="text" ' + name + ' value="' + esc(value) + '" placeholder="' + esc(p.placeholder || "") + '" pattern="' + esc(p.pattern) + '">';
  return "<label>" + esc(p.label) + " " + input + "</label>";
}

function renderCommands() {
  const groups = [];
  commands.forEach((c) => { if (!groups.includes(c.group)) groups.push(c.group); });
  $("#commands").innerHTML = groups.map((g) => '<div class="group"><h3>' + esc(g) + "</h3>" +
    commands.filter((c) => c.group === g).map((c) =>
      '<form class="cmd" data-command="' + c.id + '"><span class="name">' + esc(c.label) + "</span>" +
      c.params.map((p) => paramInput(c, p)).join("") +
      '<button type="submit" class="run primary">Run</button><span class="desc">' + esc(c.description) + "</span></form>").join("") +
    "</div>").join("");
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
    selectJob(job.id);
    loadJobs();
  } catch (err) {
    alert("Cannot run: " + err.message);
  }
}

// ---- jobs

function renderJobs() {
  if (!jobs.length) return;
  $("#jobs").innerHTML = jobs.map((j) => {
    const params = Object.entries(j.params).filter(([, v]) => v !== "" && v !== false).map(([k, v]) => k + "=" + v).join(" ");
    return '<li data-job="' + j.id + '" class="' + (selectedJob && selectedJob.id === j.id ? "selected" : "") + '">' +
      '<span class="badge ' + j.state + '">' + j.state + "</span><span>" + esc(j.label) + '</span><span class="params">' + esc(params) +
      '</span><span class="time">' + duration(j) + "</span></li>";
  }).join("");
  const busy = new Set(jobs.filter((j) => j.state === "running" || j.state === "queued").map((j) => j.command));
  document.querySelectorAll("form.cmd").forEach((f) => f.classList.toggle("busy", busy.has(f.dataset.command)));
}

async function loadJobs() {
  try {
    jobs = await api("/api/jobs");
    renderJobs();
  } catch (err) { /* hub stopped; the next poll retries */ }
}

function selectJob(id) {
  selectedJob = { id, next: 0, state: null };
  $("#job").hidden = false;
  $("#job-log").textContent = "";
  $("#job-images").innerHTML = "";
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
  const log = $("#job-log");
  const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 30;
  if (job.lines.length) log.textContent += job.lines.join("\n") + "\n";
  if (atBottom) log.scrollTop = log.scrollHeight;
  sel.next = job.next;
  $("#job-title").innerHTML = esc(job.label) + ' <span class="badge ' + job.state + '">' + job.state +
    (job.exit_code !== null && job.state !== "ok" ? " (" + job.exit_code + ")" : "") + "</span>";
  $("#job-argv").textContent = job.argv.join(" ");
  $("#job-cancel").hidden = !(job.state === "running" || job.state === "queued");
  sel.command = job.command;
  sel.params = job.params;
  if (sel.state !== job.state) {
    sel.state = job.state;
    $("#job-images").innerHTML = job.images.map((path) =>
      '<figure><a href="/files/' + esc(path) + "?t=" + job.finished + '" target="_blank"><img src="/files/' + esc(path) + "?t=" + job.finished +
      '" alt=""></a><figcaption>' + esc(path) + "</figcaption></figure>").join("");
  }
  if (job.state === "running" || job.state === "queued") setTimeout(pollJob, 600);
}

// ---- events

document.addEventListener("click", async (ev) => {
  const tabLink = ev.target.closest("[data-tab]");
  if (tabLink) { ev.preventDefault(); showTab(tabLink.dataset.tab); return; }
  const open = ev.target.closest("[data-open]");
  if (open) { showTab(open.dataset.open); return; }
  const action = ev.target.closest("[data-action]");
  if (action) {
    action.disabled = true;
    try { await api("/api/services/" + action.dataset.service + "/" + action.dataset.action, {}); } catch (err) { alert(err.message); }
    const box = document.getElementById("frame-" + action.dataset.service);
    if (box && action.dataset.action === "restart") box.innerHTML = "";
    await loadServices();
    showTab(tab);
    return;
  }
  const li = ev.target.closest("li[data-job]");
  if (li) selectJob(li.dataset.job);
});

document.addEventListener("submit", (ev) => {
  const form = ev.target.closest("form.cmd");
  if (!form) return;
  ev.preventDefault();
  const cmd = commands.find((c) => c.id === form.dataset.command);
  run(cmd.id, readParams(form, cmd));
});

$("#job-cancel").addEventListener("click", () => selectedJob && api("/api/jobs/" + selectedJob.id + "/cancel", {}).then(loadJobs));
$("#job-rerun").addEventListener("click", () => selectedJob && selectedJob.command && run(selectedJob.command, selectedJob.params));

(async () => {
  [commands] = await Promise.all([api("/api/commands"), loadServices()]);
  renderCommands();
  await loadJobs();
  showTab(location.hash.slice(1) || "home");
  if (jobs.length) selectJob(jobs[0].id);
  setInterval(loadServices, 3000);
  setInterval(loadJobs, 1500);
})();
