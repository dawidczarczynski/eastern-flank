"""Agent jobs of the unit catalog tool: run Claude Code headless (`claude -p`) for one unit at a time.

Python 3.8, stdlib only. Two job kinds, both fixed command templates - the browser only picks the kind,
the unit id and the render faction, never any part of the command line:

- `research`: `/research-unit <id>` - the agent searches the web and writes `research.json`, which is then
  merged into unit.json (`catalog.apply_research`) as unverified values for the human to check.
- `model`: `/model-unit <id> [--faction=<id>]` - builds or reworks the unit's 3D model.

Each job runs with `--permission-mode dontAsk` and an allow-list of tools (nobody can answer a permission
prompt), one job at a time (agents share the working tree and `tools/check.sh`).

Job history is saved to a JSON file (`.unit_catalog/jobs.json` for the server). Jobs that were queued or running
when the tool stopped come back as `interrupted`; any finished job with a session id can be continued: a new job
runs `claude -p <fixed continue prompt> --resume <session id>` with the same allow-list.
"""
from __future__ import annotations

import glob
import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

import catalog

KINDS = ("research", "model")
ACTIVE = ("queued", "running")
MAX_LOG = 2000  # log entries kept per job
MAX_JOBS = 50  # finished jobs kept in memory
PERSIST_LOG = 300  # log entries per job written to the state file
SAVE_EVERY = 2.0  # seconds between state file writes while a job streams its log
SESSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")  # no leading dash: it follows --resume in argv
INTERRUPTED = "the catalog tool stopped while this job was running - continue it to pick up where it stopped"
CLAUDE_ENV = "UNIT_CATALOG_CLAUDE"
VSCODE_GLOB = "~/.vscode-server/extensions/anthropic.claude-code-*/resources/native-binary/claude"


def find_claude() -> Optional[str]:
    """Path of the `claude` CLI: $UNIT_CATALOG_CLAUDE, then PATH, then the binary bundled with the VS Code extension."""
    override = os.environ.get(CLAUDE_ENV)
    if override:
        return override if os.access(override, os.X_OK) else None
    found = shutil.which("claude")
    if found:
        return found
    bundled = [p for p in glob.glob(os.path.expanduser(VSCODE_GLOB)) if os.access(p, os.X_OK)]
    return max(bundled, key=os.path.getmtime) if bundled else None


def allowed_tools(kind: str, unit_id: str, repo_root: Path) -> List[str]:
    """Tool allow-list of a job. File rules are absolute (`//abs/path`): a `cd` in the agent's shell moves the
    directory relative rules are resolved against. `Edit(...)` rules cover every file-writing tool."""
    base = "/" + str(Path(repo_root).resolve()).rstrip("/")
    udir = "%s/docs/design/units/units/%s" % (base, catalog.check_id(unit_id))
    if kind == "research":
        return ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "Skill", "Edit(%s/%s)" % (udir, catalog.RESEARCH_FILE)]
    if kind == "model":
        tools = ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "Skill", "Agent", "SendMessage"]
        # the model files, plus the spots that connect a model to the game and its contract test
        for pattern in (base + "/src/presentation/models/**", udir + "/**", base + "/src/presentation/unit_models.gd",
                        base + "/tests/unit/test_unit_model*.gd"):  # fmt: skip
            tools.append("Edit(%s)" % pattern)
        for cmd in ("tools/check.sh", "tools/test.sh", "tools/lint.sh", "tools/render_unit.sh", "tools/screenshot.sh",
                    "godot --headless", "git status", "git diff"):  # fmt: skip
            tools.append("Bash(%s:*)" % cmd)
        return tools
    raise catalog._err("kind", "must be one of %s" % ", ".join(KINDS))


def check_session(session_id: Any) -> str:
    if not isinstance(session_id, str) or not SESSION_RE.match(session_id):
        raise catalog._err("session_id", "not a Claude Code session id")
    return session_id


def build_command(claude: str, kind: str, unit_id: str, repo_root: Path, faction: str = "",
                  resume: str = "") -> List[str]:  # fmt: skip
    """argv for one job (no shell). The prompt goes right after -p; options follow. With `resume` (a session id)
    the agent continues that session with a fixed prompt instead of starting the skill again."""
    task = "/%s-unit %s" % (kind, catalog.check_id(unit_id))
    if faction:
        if kind != "model":
            raise catalog._err("faction", "only model jobs take a faction")
        task += " --faction=" + catalog.check_id(faction, "faction")
    tools = allowed_tools(kind, unit_id, repo_root)
    prompt = task
    if resume:
        prompt = ("Continue the `%s` task of this session from where it stopped (the previous run was interrupted "
                  "or ended early). Check the current state of the files first, then finish the remaining steps of "
                  "the skill and end with the usual summary." % task)  # fmt: skip
    cmd = [claude, "-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk"]
    if resume:
        cmd += ["--resume", check_session(resume)]
    return cmd + ["--allowedTools", ",".join(tools)]


def _agent_alive(pid: Any) -> bool:
    """Is a `claude` process with this pid still running (e.g. left behind when the tool was killed)?"""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return b"claude" in f.read()
    except OSError:
        return False


def _short(value: Any, limit: int = 160) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _tool_summary(name: str, args: Any) -> str:
    if not isinstance(args, dict):
        return name
    for key in ("file_path", "command", "pattern", "query", "url", "description", "skill", "path"):
        if isinstance(args.get(key), str):
            return "%s: %s" % (name, _short(args[key], 140))
    return name


def parse_stream_line(line: str) -> List[Dict[str, Any]]:
    """Turn one stream-json line into log entries `{"kind": text|tool|info|error|result, "text", ...}`."""
    line = line.strip()
    if not line:
        return []
    try:
        msg = json.loads(line)
    except ValueError:
        return [{"kind": "info", "text": _short(line, 400)}]
    if not isinstance(msg, dict):
        return []
    mtype = msg.get("type")
    sub = msg.get("parent_tool_use_id") is not None
    if mtype == "system" and msg.get("subtype") == "init":
        return [{"kind": "info", "text": "session %s started (%s)" % (msg.get("session_id", "?"), msg.get("model", "?")),
                 "session_id": msg.get("session_id")}]  # fmt: skip
    if mtype == "assistant":
        out = []
        for block in (msg.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and str(block.get("text", "")).strip():
                out.append({"kind": "text", "text": block["text"].strip(), "sub": sub})
            elif block.get("type") == "tool_use":
                out.append({"kind": "tool", "text": _tool_summary(str(block.get("name")), block.get("input")), "sub": sub})
        return out
    if mtype == "user":
        out = []
        for block in (msg.get("message") or {}).get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_result" and block.get("is_error"):
                content = block.get("content")
                text = content if isinstance(content, str) else json.dumps(content, ensure_ascii=False)
                out.append({"kind": "error", "text": _short(text, 300), "sub": sub})
        return out
    if mtype == "result":
        return [{"kind": "result", "text": str(msg.get("result") or ""), "is_error": bool(msg.get("is_error")),
                 "cost_usd": msg.get("total_cost_usd"), "session_id": msg.get("session_id")}]  # fmt: skip
    return []


class Job:
    STORED = ("id", "kind", "unit_id", "faction", "state", "created", "started", "finished", "result", "error",
              "cost_usd", "session_id", "report", "changed_files", "resume_of", "resume_session", "pid")  # fmt: skip

    def __init__(self, job_id: str, kind: str, unit_id: str, faction: str, resume_of: str = "",
                 resume_session: str = "") -> None:  # fmt: skip
        self.id = job_id
        self.kind = kind
        self.unit_id = unit_id
        self.faction = faction
        self.resume_of = resume_of  # id of the job this one continues
        self.resume_session = resume_session  # session id passed to --resume
        self.pid: Optional[int] = None
        self.state = "queued"
        self.created = time.time()
        self.started: Optional[float] = None
        self.finished: Optional[float] = None
        self.log: List[Dict[str, Any]] = []
        self.log_offset = 0  # entries dropped from the front
        self.result = ""
        self.error = ""
        self.cost_usd: Optional[float] = None
        self.session_id = ""
        self.report: Optional[Dict[str, Any]] = None
        self.changed_files: List[str] = []
        self.proc: Optional[Any] = None
        self.cancel_requested = False
        self.stopping = False  # the tool is shutting down: the job ends as interrupted

    def add_log(self, entry: Dict[str, Any]) -> None:
        entry["t"] = round(time.time(), 1)
        self.log.append(entry)
        if len(self.log) > MAX_LOG:
            drop = len(self.log) - MAX_LOG
            del self.log[:drop]
            self.log_offset += drop

    def resumable(self) -> bool:
        return self.state not in ACTIVE and bool(SESSION_RE.match(self.session_id or ""))

    def summary(self) -> Dict[str, Any]:
        return {"id": self.id, "kind": self.kind, "unit_id": self.unit_id, "faction": self.faction,
                "state": self.state, "created": self.created, "started": self.started, "finished": self.finished,
                "error": self.error, "cost_usd": self.cost_usd, "session_id": self.session_id,
                "resume_of": self.resume_of, "resumable": self.resumable(),
                "log_size": self.log_offset + len(self.log)}  # fmt: skip

    def to_dict(self) -> Dict[str, Any]:
        out = {key: getattr(self, key) for key in self.STORED}
        out["log"] = self.log[-PERSIST_LOG:]
        out["log_offset"] = self.log_offset + len(self.log) - len(out["log"])
        return out

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Job":
        job = cls(str(data["id"]), str(data["kind"]), str(data["unit_id"]), str(data.get("faction") or ""))
        for key in cls.STORED[4:]:
            if key in data:
                setattr(job, key, data[key])
        job.log = [e for e in data.get("log") or [] if isinstance(e, dict)]
        job.log_offset = int(data.get("log_offset") or 0)
        if job.state in ACTIVE:  # the tool stopped without a clean shutdown
            job.state = "interrupted" if job.state == "running" else "cancelled"
            job.error = INTERRUPTED if job.state == "interrupted" else "the catalog tool stopped before this job started"
            job.finished = job.finished or time.time()
        return job

    def detail(self, since: int = 0) -> Dict[str, Any]:
        start = max(0, since - self.log_offset)
        out = self.summary()
        out.update({"result": self.result, "report": self.report, "changed_files": self.changed_files,
                    "log_from": self.log_offset + start, "log": self.log[start:]})  # fmt: skip
        return out


Popen = Callable[..., Any]


class JobManager:
    """FIFO queue with a single worker thread. `popen` is injectable for tests."""

    def __init__(self, repo_root: Path, catalog_root: Path, claude: Optional[str],
                 popen: Popen = subprocess.Popen, state_file: Optional[Path] = None) -> None:  # fmt: skip
        self.repo_root = Path(repo_root)
        self.state_file = Path(state_file) if state_file else None
        self.catalog_root = Path(catalog_root)
        self.claude = claude
        self._popen = popen
        self._jobs: Dict[str, Job] = {}
        self._queue: List[Job] = []
        self._lock = threading.Lock()
        self._wake = threading.Condition(self._lock)
        self._counter = 0
        self._worker: Optional[threading.Thread] = None
        self._saved_at = 0.0
        self._load()

    # ---- API used by the server
    def status(self) -> Dict[str, Any]:
        display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
        return {"available": self.claude is not None, "claude": self.claude or "", "display": display,
                "hint": "" if self.claude else "Claude Code CLI not found: install it (`claude` on PATH) "
                "or set %s to its path, log in once with `claude`, then restart the tool." % CLAUDE_ENV}  # fmt: skip

    def list(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [j.summary() for j in sorted(self._jobs.values(), key=lambda j: j.created, reverse=True)]

    def get(self, job_id: str, since: int = 0) -> Dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                raise catalog._err("job", "job not found", 404)
            return job.detail(since)

    def submit(self, kind: Any, unit_id: Any, faction: Any = "") -> Dict[str, Any]:
        if self.claude is None:
            raise catalog._err("ai", self.status()["hint"], 503)
        if kind not in KINDS:
            raise catalog._err("kind", "must be one of %s" % ", ".join(KINDS))
        faction = faction or ""
        if not isinstance(faction, str):
            raise catalog._err("faction", "must be a faction id")
        build_command(self.claude, kind, unit_id, self.repo_root, faction)  # validates the ids
        catalog.load_unit(self.catalog_root, unit_id)  # 404 for unknown units
        if faction and not catalog.faction_path(self.catalog_root, faction).is_file():
            raise catalog._err("faction", "unknown faction %r" % faction)
        with self._lock:
            busy = [j for j in self._jobs.values() if j.unit_id == unit_id and j.state in ACTIVE]
            if busy:
                raise catalog._err("unit_id", "a %s job for this unit is already %s" % (busy[0].kind, busy[0].state), 409)
            self._counter += 1
            job = Job(self._new_id(), kind, unit_id, faction)
            self._enqueue(job)
            out = job.summary()
        self._save()
        return out

    def resume(self, job_id: str) -> Dict[str, Any]:
        """Queue a job that continues `job_id`'s Claude Code session (same kind, unit, faction and allow-list)."""
        if self.claude is None:
            raise catalog._err("ai", self.status()["hint"], 503)
        with self._lock:
            old = self._jobs.get(job_id)
            if old is None:
                raise catalog._err("job", "job not found", 404)
            if old.state in ACTIVE:
                raise catalog._err("job", "the job is still %s" % old.state, 409)
            session = check_session(old.session_id)
            busy = [j for j in self._jobs.values() if j.unit_id == old.unit_id and j.state in ACTIVE]
            if busy:
                raise catalog._err("unit_id", "a %s job for this unit is already %s" % (busy[0].kind, busy[0].state), 409)
            if _agent_alive(old.pid):
                raise catalog._err("job", "the agent process of this job (pid %d) is still running - stop it first" % old.pid, 409)
            self._counter += 1
            job = Job(self._new_id(), old.kind, old.unit_id, old.faction, old.id, session)
            self._enqueue(job)
            out = job.summary()
        self._save()
        return out

    def last_for_unit(self, unit_id: str) -> Optional[Dict[str, Any]]:
        """The unit's newest job if it can be continued and did not end cleanly (interrupted, failed, cancelled)."""
        with self._lock:
            mine = sorted((j for j in self._jobs.values() if j.unit_id == unit_id), key=lambda j: j.created)
            if mine and mine[-1].state in ("interrupted", "failed", "cancelled") and mine[-1].resumable():
                return mine[-1].summary()
        return None

    def cancel(self, job_id: str) -> Dict[str, Any]:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                raise catalog._err("job", "job not found", 404)
            if job.state == "queued":
                self._queue.remove(job)
                job.state = "cancelled"
                job.finished = time.time()
            elif job.state == "running":
                job.cancel_requested = True
                self._terminate(job)
            out = job.summary()
        self._save()
        return out

    def active_for_unit(self, unit_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            for j in self._jobs.values():
                if j.unit_id == unit_id and j.state in ACTIVE:
                    return j.summary()
        return None

    def shutdown(self) -> None:
        """Stop everything. Running jobs end as `interrupted` (saved first: the process may exit right after)."""
        with self._lock:
            for job in self._queue:
                job.state = "cancelled"
                job.finished = time.time()
            self._queue.clear()
            running = [j for j in self._jobs.values() if j.state == "running"]
            for job in running:
                job.stopping = True
                job.state = "interrupted"
                job.error = INTERRUPTED
                job.finished = time.time()
        self._save()
        for job in running:
            self._terminate(job)

    def wait_idle(self, timeout: float = 10.0) -> bool:
        """Test helper: wait until no job is queued or running."""
        end = time.time() + timeout
        while time.time() < end:
            with self._lock:
                if not any(j.state in ACTIVE for j in self._jobs.values()):
                    return True
            time.sleep(0.02)
        return False

    # ---- state file
    def _new_id(self) -> str:
        return "%s-%d" % (time.strftime("%H%M%S"), self._counter)

    def _enqueue(self, job: Job) -> None:
        self._jobs[job.id] = job
        self._queue.append(job)
        self._prune()
        self._ensure_worker()
        self._wake.notify()

    def _load(self) -> None:
        if self.state_file is None or not self.state_file.is_file():
            return
        try:
            data = json.loads(self.state_file.read_text(encoding="utf-8"))
            for item in data.get("jobs") or []:
                job = Job.from_dict(item)
                self._jobs[job.id] = job
            self._counter = int(data.get("counter") or len(self._jobs))
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            print("Ignoring unreadable job history %s: %s" % (self.state_file, exc), flush=True)

    def _save(self, throttle: bool = False) -> None:
        if self.state_file is None:
            return
        with self._lock:
            if throttle and time.time() - self._saved_at < SAVE_EVERY:
                return
            self._saved_at = time.time()
            data = {"version": 1, "counter": self._counter,
                    "jobs": [j.to_dict() for j in sorted(self._jobs.values(), key=lambda j: j.created)]}  # fmt: skip
            text = json.dumps(data, ensure_ascii=False, indent=1)
            try:
                self.state_file.parent.mkdir(parents=True, exist_ok=True)
                tmp = self.state_file.with_name(self.state_file.name + ".tmp")
                tmp.write_text(text, encoding="utf-8")
                os.replace(str(tmp), str(self.state_file))
            except OSError as exc:  # history is a convenience: never break a job over it
                print("Cannot save job history %s: %s" % (self.state_file, exc), flush=True)

    # ---- worker
    def _prune(self) -> None:
        done = sorted((j for j in self._jobs.values() if j.state not in ACTIVE), key=lambda j: j.created)
        for job in done[: max(0, len(self._jobs) - MAX_JOBS)]:
            del self._jobs[job.id]

    def _ensure_worker(self) -> None:
        if self._worker is None or not self._worker.is_alive():
            self._worker = threading.Thread(target=self._loop, name="unit-catalog-jobs", daemon=True)
            self._worker.start()

    def _loop(self) -> None:
        while True:
            with self._lock:
                while not self._queue:
                    self._wake.wait()
                job = self._queue.pop(0)
                job.state = "running"
                job.started = time.time()
            self._save()
            try:
                self._run(job)
            except Exception as exc:  # pragma: no cover - keep the worker alive
                job.error = "internal error: %s" % exc
                job.state = "failed"
            if not job.stopping:
                job.finished = time.time()
            self._save()

    def _terminate(self, job: Job) -> None:
        proc = job.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)  # the agent's own children (godot, tests) too
        except (OSError, AttributeError):
            proc.terminate()

    def _run(self, job: Job) -> None:
        cmd = build_command(str(self.claude), job.kind, job.unit_id, self.repo_root, job.faction, job.resume_session)
        env = dict(os.environ)
        env.pop("CLAUDECODE", None)  # the tool may itself be started from a Claude Code session
        if job.kind == "model" and not self.status()["display"]:
            job.add_log({"kind": "error", "text": "no DISPLAY/WAYLAND_DISPLAY - the render step will probably fail"})
        if job.kind == "research" and not job.resume_session:
            stale = catalog.unit_dir(self.catalog_root, job.unit_id) / catalog.RESEARCH_FILE
            if stale.exists():
                stale.unlink()
        if job.resume_session:
            job.add_log({"kind": "info", "text": "continuing session %s of job %s" % (job.resume_session, job.resume_of)})
        job.add_log({"kind": "info", "text": "$ claude -p %r (%d allowed tools)" % (cmd[2], len(cmd[-1].split(",")))})
        try:
            proc = self._popen(cmd, cwd=str(self.repo_root), env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                               start_new_session=True)  # fmt: skip
        except OSError as exc:
            job.error = "cannot start claude: %s" % exc
            job.state = "failed"
            return
        with self._lock:
            job.proc = proc
            job.pid = getattr(proc, "pid", None)
            if job.cancel_requested or job.stopping:
                self._terminate(job)
        result: Optional[Dict[str, Any]] = None
        for line in proc.stdout:
            for entry in parse_stream_line(line):
                with self._lock:
                    if entry.get("session_id"):
                        job.session_id = entry["session_id"]
                    if entry["kind"] == "result":
                        result = entry
                        job.result = entry["text"]
                        job.cost_usd = entry.get("cost_usd")
                    else:
                        job.add_log(entry)
            self._save(throttle=True)
        code = proc.wait()
        if job.stopping:
            return
        if job.cancel_requested:
            job.state = "cancelled"
            return
        if code != 0 or result is None or result.get("is_error"):
            job.error = "claude exited with code %d" % code if code != 0 else "the agent reported an error"
            job.state = "failed"
            return
        try:
            self._after(job)
        except catalog.CatalogError as exc:
            job.error = "; ".join("%s: %s" % (e["field"], e["message"]) for e in exc.errors)
            job.state = "failed"
            return
        job.state = "done"

    def _after(self, job: Job) -> None:
        if job.kind == "research":
            if not (catalog.unit_dir(self.catalog_root, job.unit_id) / catalog.RESEARCH_FILE).is_file():
                raise catalog._err("research", "the agent did not write %s - see its summary" % catalog.RESEARCH_FILE)
            job.report = catalog.apply_research(self.catalog_root, job.unit_id)
        else:
            try:
                out = subprocess.run(["git", "status", "--porcelain"], cwd=str(self.repo_root), capture_output=True,
                                     text=True, timeout=20, check=False).stdout  # fmt: skip
                job.changed_files = [line[3:] for line in out.splitlines() if line.strip()]
            except (OSError, subprocess.SubprocessError):
                job.changed_files = []
