"""Agent jobs of the unit catalog tool: run Claude Code headless (`claude -p`) for one unit at a time.

Python 3.8, stdlib only. Two job kinds, both fixed command templates - the browser only picks the kind,
the unit id and the render faction, never any part of the command line:

- `research`: `/research-unit <id>` - the agent searches the web and writes `research.json`, which is then
  merged into unit.json (`catalog.apply_research`) as unverified values for the human to check.
- `model`: `/model-unit <id> [--faction=<id>]` - builds or reworks the unit's 3D model.

Each job runs with `--permission-mode dontAsk` and an allow-list of tools (nobody can answer a permission
prompt), one job at a time (agents share the working tree and `tools/check.sh`).
"""
from __future__ import annotations

import glob
import json
import os
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
        for pattern in (base + "/src/presentation/models/**", udir + "/**"):
            tools.append("Edit(%s)" % pattern)
        for cmd in ("tools/check.sh", "tools/test.sh", "tools/lint.sh", "tools/render_unit.sh", "tools/screenshot.sh",
                    "godot --headless", "git status", "git diff"):  # fmt: skip
            tools.append("Bash(%s:*)" % cmd)
        return tools
    raise catalog._err("kind", "must be one of %s" % ", ".join(KINDS))


def build_command(claude: str, kind: str, unit_id: str, repo_root: Path, faction: str = "") -> List[str]:
    """argv for one job (no shell). The prompt goes right after -p; options follow."""
    prompt = "/%s-unit %s" % (kind, catalog.check_id(unit_id))
    if faction:
        if kind != "model":
            raise catalog._err("faction", "only model jobs take a faction")
        prompt += " --faction=" + catalog.check_id(faction, "faction")
    tools = allowed_tools(kind, unit_id, repo_root)
    return [claude, "-p", prompt, "--output-format", "stream-json", "--verbose",
            "--permission-mode", "dontAsk", "--allowedTools", ",".join(tools)]  # fmt: skip


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
    def __init__(self, job_id: str, kind: str, unit_id: str, faction: str) -> None:
        self.id = job_id
        self.kind = kind
        self.unit_id = unit_id
        self.faction = faction
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

    def add_log(self, entry: Dict[str, Any]) -> None:
        entry["t"] = round(time.time(), 1)
        self.log.append(entry)
        if len(self.log) > MAX_LOG:
            drop = len(self.log) - MAX_LOG
            del self.log[:drop]
            self.log_offset += drop

    def summary(self) -> Dict[str, Any]:
        return {"id": self.id, "kind": self.kind, "unit_id": self.unit_id, "faction": self.faction,
                "state": self.state, "created": self.created, "started": self.started, "finished": self.finished,
                "error": self.error, "cost_usd": self.cost_usd, "session_id": self.session_id,
                "log_size": self.log_offset + len(self.log)}  # fmt: skip

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
                 popen: Popen = subprocess.Popen) -> None:  # fmt: skip
        self.repo_root = Path(repo_root)
        self.catalog_root = Path(catalog_root)
        self.claude = claude
        self._popen = popen
        self._jobs: Dict[str, Job] = {}
        self._queue: List[Job] = []
        self._lock = threading.Lock()
        self._wake = threading.Condition(self._lock)
        self._counter = 0
        self._worker: Optional[threading.Thread] = None

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
            job = Job("%s-%d" % (time.strftime("%H%M%S"), self._counter), kind, unit_id, faction)
            self._jobs[job.id] = job
            self._queue.append(job)
            self._prune()
            self._ensure_worker()
            self._wake.notify()
            return job.summary()

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
            return job.summary()

    def active_for_unit(self, unit_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            for j in self._jobs.values():
                if j.unit_id == unit_id and j.state in ACTIVE:
                    return j.summary()
        return None

    def shutdown(self) -> None:
        with self._lock:
            for job in self._queue:
                job.state = "cancelled"
            self._queue.clear()
            running = [j for j in self._jobs.values() if j.state == "running"]
        for job in running:
            job.cancel_requested = True
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
            try:
                self._run(job)
            except Exception as exc:  # pragma: no cover - keep the worker alive
                job.error = "internal error: %s" % exc
                job.state = "failed"
            job.finished = time.time()

    def _terminate(self, job: Job) -> None:
        proc = job.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)  # the agent's own children (godot, tests) too
        except (OSError, AttributeError):
            proc.terminate()

    def _run(self, job: Job) -> None:
        cmd = build_command(str(self.claude), job.kind, job.unit_id, self.repo_root, job.faction)
        env = dict(os.environ)
        env.pop("CLAUDECODE", None)  # the tool may itself be started from a Claude Code session
        if job.kind == "model" and not self.status()["display"]:
            job.add_log({"kind": "error", "text": "no DISPLAY/WAYLAND_DISPLAY - the render step will probably fail"})
        if job.kind == "research":
            stale = catalog.unit_dir(self.catalog_root, job.unit_id) / catalog.RESEARCH_FILE
            if stale.exists():
                stale.unlink()
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
            if job.cancel_requested:
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
        code = proc.wait()
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
