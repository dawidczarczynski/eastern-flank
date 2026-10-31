"""Claude chat of the devtools hub: Claude Code sessions the human talks to in the browser. Python 3.8, stdlib only.

A session is one `claude -p --input-format stream-json --output-format stream-json` process, driven like the
Agent SDK drives it (ADR 0017): every message goes to its stdin as a stream-json user message - also while a turn
runs (the CLI folds it into the work) and slash commands like `/compact` - and the control protocol on the same
pipes carries what the IDE would show: permission prompts and `AskUserQuestion` (`can_use_tool` requests, answered
from the browser), the session's slash commands (`initialize`) and Stop (`interrupt`, the process stays alive).

The session behaves like Claude Code in the IDE: `auto` permission mode plus the human's own settings, no extra
rules and no extra system prompt - except that a task session runs on TASK_MODEL (`--model sonnet`, also when
resumed): the orchestrator is always Sonnet, opus tasks are implemented by opus agents. A session started from the backlog opens with `/implement-task <TASK-ID>`; a
free chat opens with the human's text. When the process is gone (a devtools restart, a crash, too many idle
processes) the next message starts a new one with `--resume <session id>`. History is saved to
`.devtools/chats.json` (git-ignored); one devtools instance owns it (`lock_history`).

Usage calibration (TASK-109, tools/usage_forecast.py): the latest limit windows go to `.devtools/limits.json` (the
backlog view reads them), and every turn of a task session appends one sample - utilization and the session's
weighted cost from its transcript (tools/task_cost.py) at the turn's start and end, flagged `parallel` when another
devtools session worked meanwhile and `stale` when the CLI reported no limits during the turn.
"""
from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
import backlog  # noqa: E402  (tools/backlog.py)
import claude_cli  # noqa: E402
import task_cost  # noqa: E402  (tools/task_cost.py)
import usage_forecast  # noqa: E402  (tools/usage_forecast.py)

CLAUDE_ENV = "DEVTOOLS_CLAUDE"
TASK_RE = re.compile(r"^TASK-\d+[a-z]?$")
MAX_TEXT = 32 * 1024  # characters per message
MAX_LOG = 4000  # log entries kept per session
PERSIST_LOG = 1500  # log entries per session written to the state file
MAX_SESSIONS = 40
MAX_IDLE_PROCESSES = 4  # idle Claude processes kept alive; older ones stop and resume on their next message
SAVE_EVERY = 2.0  # seconds between state file writes while a session streams
INTERRUPT_GRACE = 8.0  # seconds a Stop waits for the turn to end before the process is killed
TASK_SHOWN_FOR = 30.0  # seconds a finished subagent / background task stays in the panel
TASK_DONE = ("completed", "failed", "killed", "stopped", "cancelled", "error")
CLOSED_STATUSES = ("done", "merged", "idea")  # tasks the backlog button does not implement
PERMISSION_MODE = "auto"  # what the human uses in the IDE
TASK_MODEL = "sonnet"  # the /implement-task orchestrator; opus tasks get opus agents (the skill's step 4)


class ChatError(Exception):
    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status = status


def find_claude() -> Optional[str]:
    """Path of the `claude` CLI: $DEVTOOLS_CLAUDE, then PATH, then the binary bundled with the VS Code extension."""
    return claude_cli.find_claude(CLAUDE_ENV)


def lock_history(state_file: Path) -> Optional[Any]:
    """Hold `<state_file>.lock` for the life of the process (an open file with an flock), or None when another
    devtools instance holds it: two hubs would overwrite each other's history."""
    import fcntl

    state_file.parent.mkdir(parents=True, exist_ok=True)
    handle = open(str(state_file) + ".lock", "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def check_task(task_id: Any) -> str:
    if not isinstance(task_id, str) or not TASK_RE.match(task_id):
        raise ChatError("not a task id (TASK-123)")
    return task_id


def build_command(claude: str, resume: str = "", model: str = "") -> List[str]:
    """argv of one chat process (no shell). Messages, the first prompt too, and control responses arrive on stdin;
    permission prompts come back as `can_use_tool` control requests (`--permission-prompt-tool stdio`). `model`
    overrides the human's default (task sessions: TASK_MODEL)."""
    cmd = [claude, "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--permission-mode", PERMISSION_MODE, "--permission-prompt-tool", "stdio"]  # fmt: skip
    if model:
        cmd += ["--model", model]
    if resume:
        if not claude_cli.SESSION_RE.match(resume):
            raise ChatError("not a Claude Code session id")
        cmd += ["--resume", resume]
    return cmd


def user_message(text: str) -> str:
    return json.dumps({"type": "user", "message": {"role": "user", "content": text}}, ensure_ascii=False) + "\n"


def control_request(request_id: str, request: Dict[str, Any]) -> str:
    return json.dumps({"type": "control_request", "request_id": request_id, "request": request}) + "\n"


def control_response(request_id: str, response: Dict[str, Any]) -> str:
    return json.dumps({"type": "control_response", "response": {"subtype": "success", "request_id": request_id,
                                                                "response": response}}, ensure_ascii=False) + "\n"  # fmt: skip


def backlog_task(repo_root: Path, task_id: str) -> Optional[Dict[str, str]]:
    """`{id, title, status}` of a BACKLOG.md row (status = its first word(s), e.g. `ready`, `in progress`)."""
    path = Path(repo_root) / "docs" / "tasks" / "BACKLOG.md"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    lines = text.splitlines()
    for row in backlog.parse_rows(text):
        if row["id"] == task_id:
            cells = [c.strip() for c in lines[row["line"]].strip().strip("|").split("|")]
            status = row["status"]
            status = "in progress" if status.startswith("in progress") else "to playtest" if status.startswith(
                "to playtest") else (status.split() or [""])[0]  # fmt: skip
            return {"id": task_id, "title": cells[1].replace("`", "") if len(cells) > 1 else "", "status": status}
    return None


class Session:
    STORED = ("id", "task", "title", "session_id", "created", "updated", "cost_usd", "error", "pid", "changed_files",
              "context_tokens", "context_window")  # fmt: skip

    def __init__(self, sid: str, title: str, task: str = "") -> None:
        self.id = sid
        self.task = task
        self.title = title
        self.session_id = ""
        self.created = time.time()
        self.updated = self.created
        self.cost_usd: Optional[float] = None
        self.cost_base = 0.0  # cost of the earlier processes (total_cost_usd counts per process)
        self.error = ""
        self.pid: Optional[int] = None
        self.changed_files: List[str] = []
        self.context_tokens: Optional[int] = None  # the main agent's context after its last API call
        self.context_window: Optional[int] = None
        self.log: List[Dict[str, Any]] = []
        self.log_offset = 0
        self.proc: Optional[Any] = None
        self.busy = False  # a turn is running
        self.pending: Dict[str, Dict[str, Any]] = {}  # request id → permission prompt / question waiting for the human
        self.tasks: Dict[str, Dict[str, Any]] = {}  # task id → subagent / background task (running or just finished)
        self.stop_requested = False
        self.used = self.created  # last time a message was sent (which idle process stops first)
        self.sample: Optional[Dict[str, Any]] = None  # the running turn's calibration sample (task sessions)
        self.weighted_cost: Optional[float] = None  # the transcript's weighted cost at the end of the last turn

    def active(self) -> bool:
        """Spending tokens now: a turn runs or a subagent / background task does."""
        return self.alive() and (self.busy or any(t["status"] == "running" for t in self.tasks.values()))

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def state(self) -> str:
        if self.alive():
            return "asking" if self.pending else "working" if self.busy else "idle"
        return "failed" if self.error else "stopped"

    def add(self, entry: Dict[str, Any]) -> None:
        entry["t"] = round(time.time(), 1)
        self.log.append(entry)
        self.updated = entry["t"]
        if len(self.log) > MAX_LOG:
            drop = len(self.log) - MAX_LOG
            del self.log[:drop]
            self.log_offset += drop

    def summary(self) -> Dict[str, Any]:
        return {"id": self.id, "task": self.task, "title": self.title, "state": self.state(),
                "session_id": self.session_id, "cost_usd": self.cost_usd, "created": self.created,
                "updated": self.updated, "error": self.error, "log_size": self.log_offset + len(self.log),
                "changed": len(self.changed_files), "context_tokens": self.context_tokens,
                "context_window": self.context_window, "pending": len(self.pending),
                "agents": sum(1 for t in self.tasks.values() if t["status"] == "running")}  # fmt: skip

    def detail(self, since: int = 0) -> Dict[str, Any]:
        start = max(0, since - self.log_offset)
        out = self.summary()
        out.update(log=self.log[start:], log_from=self.log_offset + start, changed_files=self.changed_files,
                   pending_requests=list(self.pending.values()), tasks=self.visible_tasks(),
                   resume_command="claude --resume %s" % self.session_id if self.session_id else "")  # fmt: skip
        return out

    def track_task(self, event: str, msg: Dict[str, Any]) -> None:
        """Follow the CLI's task events. Shown: subagents, and background tasks the main agent started."""
        task_id = str(msg.get("task_id") or "")
        if not task_id:
            return
        if event == "task_started":
            agent = msg.get("task_type") == "local_agent"
            if not agent and (not msg.get("is_backgrounded") or msg.get("owned_by_subagent")):
                return  # a foreground command, or one a subagent runs: its tool line says enough
            self.tasks[task_id] = {
                "id": task_id, "agent": agent, "type": str(msg.get("subagent_type") or msg.get("task_type") or "task"),
                "description": str(msg.get("description") or ""), "background": bool(msg.get("is_backgrounded")),
                "depth": int(msg.get("spawn_depth") or 1), "started": time.time(), "activity": "", "tokens": None,
                "tool_uses": None, "status": "running", "finished": None,
            }  # fmt: skip
            return
        task = self.tasks.get(task_id)
        if task is None:
            return
        if event == "task_progress":
            usage = msg.get("usage") if isinstance(msg.get("usage"), dict) else {}
            task.update(activity=str(msg.get("description") or ""), tokens=usage.get("total_tokens"), tool_uses=usage.get("tool_uses"))
        status = (msg.get("patch") or {}).get("status") if event == "task_updated" else msg.get("status") if event == "task_notification" else None
        if status in TASK_DONE and task["status"] == "running":
            task.update(status=status, finished=time.time())

    def visible_tasks(self) -> List[Dict[str, Any]]:
        """Running tasks, plus the ones that finished in the last few seconds (dropped after that)."""
        now = time.time()
        for task_id in [k for k, t in self.tasks.items() if t["finished"] and now - t["finished"] > TASK_SHOWN_FOR]:
            del self.tasks[task_id]
        return sorted(self.tasks.values(), key=lambda t: t["started"])

    def to_dict(self) -> Dict[str, Any]:
        out = {key: getattr(self, key) for key in self.STORED}
        out["log"] = self.log[-PERSIST_LOG:]
        out["log_offset"] = self.log_offset + len(self.log) - len(out["log"])
        return out

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Session":
        s = cls(str(data["id"]), str(data.get("title") or ""), str(data.get("task") or ""))
        for key in cls.STORED[3:]:
            if key in data:
                setattr(s, key, data[key])
        s.log = [e for e in data.get("log") or [] if isinstance(e, dict)]
        s.log_offset = int(data.get("log_offset") or 0)
        s.cost_base = float(s.cost_usd or 0.0)
        return s


Popen = Callable[..., Any]


class ChatManager:
    """Claude sessions of the hub. `popen` and `changed` (`git status` lines) are injectable for tests."""

    def __init__(self, repo_root: Path, claude: Optional[str], popen: Popen = subprocess.Popen,
                 state_file: Optional[Path] = None, changed: Optional[Callable[[], List[str]]] = None,
                 unavailable: str = "", calibration_file: Optional[Path] = None, limits_file: Optional[Path] = None,
                 projects_dir: Optional[Path] = None) -> None:  # fmt: skip
        self.repo_root = Path(repo_root)
        self.calibration_file = Path(calibration_file) if calibration_file else None  # None: no samples recorded
        self.limits_file = Path(limits_file) if limits_file else None
        self.projects_dir = Path(projects_dir) if projects_dir else task_cost.project_dir(self.repo_root)
        self._limits_written = 0.0
        self.claude = None if unavailable else claude
        self._unavailable = unavailable  # why the chat is off although the CLI may exist
        self.state_file = Path(state_file) if state_file else None
        self._popen = popen
        self._changed = changed or self._git_status
        self._sessions: Dict[str, Session] = {}
        self._lock = threading.RLock()
        self._write_lock = threading.Lock()  # the state file is written outside `_lock`
        self._counter = 0
        self._requests = 0
        self._saved_at = 0.0
        self.limits: Optional[Dict[str, Any]] = None  # the subscription's usage windows, as last reported by the CLI
        self.commands: List[Dict[str, str]] = []  # slash commands, from the last `initialize` answer
        self._load()

    # ---- API used by the server
    def status(self) -> Dict[str, Any]:
        return {"available": self.claude is not None, "claude": self.claude or "",
                "hint": "" if self.claude else self._unavailable or "Claude Code CLI not found: install it (`claude` on "
                "PATH) or set %s to its path, log in once with `claude`, then restart devtools." % CLAUDE_ENV,
                "permission_mode": PERMISSION_MODE, "limits": self.limits, "commands": self.commands}  # fmt: skip

    def list(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [s.summary() for s in sorted(self._sessions.values(), key=lambda s: s.updated, reverse=True)]

    def get(self, sid: str, since: int = 0) -> Dict[str, Any]:
        with self._lock:
            return self._find(sid).detail(since)

    def create(self, task: Any = None, text: Any = None) -> Dict[str, Any]:
        """A new session: `task` → `/implement-task <task>` (an existing session of that task is returned instead),
        otherwise a free chat starting with `text`."""
        self._require_claude()
        if task is not None:
            task = check_task(task)
            row = backlog_task(self.repo_root, task)
            if row is None:
                raise ChatError("%s is not in docs/tasks/BACKLOG.md" % task, 404)
            with self._lock:
                existing = [s for s in self._sessions.values() if s.task == task]
                if existing:
                    out = max(existing, key=lambda s: s.created).summary()
                    out["existing"] = True
                    return out
            if row["status"] in CLOSED_STATUSES:
                raise ChatError("%s is %s" % (task, row["status"]), 409)
            title, prompt = "%s · %s" % (task, row["title"]), "/implement-task %s" % task
        else:
            prompt = self._check_text(text)
            title = claude_cli.short(prompt, 70)
        with self._lock:
            self._counter += 1
            s = Session("%s-%d" % (time.strftime("%m%d%H%M%S"), self._counter), title, task or "")
            self._sessions[s.id] = s
            self._prune()
            self._send(s, prompt)
            out = s.summary()
        self._save()
        return out

    def send(self, sid: str, text: Any) -> Dict[str, Any]:
        """A message to the session - while a turn runs too: the CLI folds it into the work, as the IDE does."""
        self._require_claude()
        text = self._check_text(text)
        with self._lock:
            s = self._find(sid)
            if not s.alive() and claude_cli.agent_alive(s.pid):
                raise ChatError("the old Claude process of this chat (pid %d) is still running - stop it first" % s.pid, 409)
            self._send(s, text)
            out = s.summary()
        self._save()
        return out

    def answer(self, sid: str, request_id: Any, behavior: Any, answers: Any = None, message: Any = "") -> Dict[str, Any]:
        """The human's answer to a pending prompt: `allow`, `always` (allow and add the CLI's suggested rules),
        `deny` (with an optional message), or `answers` ({question: answer}) for `AskUserQuestion`."""
        with self._lock:
            s = self._find(sid)
            pending = s.pending.get(request_id) if isinstance(request_id, str) else None
            if pending is None:
                raise ChatError("this request was already answered or has expired", 404)
            if pending["tool"] == "AskUserQuestion" and behavior != "deny":
                response = {"behavior": "allow", "updatedInput": dict(pending["input"], answers=self._check_answers(pending, answers))}
                done = {"kind": "answered", "request_id": request_id, "answers": response["updatedInput"]["answers"]}
            elif behavior in ("allow", "always"):
                response = {"behavior": "allow", "updatedInput": pending["input"]}
                if behavior == "always" and pending["suggestions"]:
                    response["updatedPermissions"] = pending["suggestions"]
                done = {"kind": "answered", "request_id": request_id, "behavior": behavior}
            elif behavior == "deny":
                note = message.strip() if isinstance(message, str) and message.strip() else ""
                response = {"behavior": "deny", "message": note or "The user denied this action."}
                done = {"kind": "answered", "request_id": request_id, "behavior": "deny", "text": note}
            else:
                raise ChatError("behavior must be allow, always or deny")
            del s.pending[request_id]
            s.add(done)
            self._write(s, control_response(request_id, response))
            out = s.summary()
        self._save()
        return out

    def stop(self, sid: str) -> Dict[str, Any]:
        """Interrupt the running turn (like Esc in the IDE); the process stays. Killed if the turn doesn't end."""
        with self._lock:
            s = self._find(sid)
            if s.alive() and (s.busy or s.pending):
                s.pending.clear()
                self._requests += 1
                self._write(s, control_request("interrupt_%d" % self._requests, {"subtype": "interrupt"}))
                threading.Thread(target=self._kill_if_stuck, args=(s, s.proc), daemon=True).start()
            out = s.summary()
        return out

    def shutdown(self) -> None:
        with self._lock:
            live = [s for s in self._sessions.values() if s.alive()]
            for s in live:
                s.stop_requested = True
                if s.busy:
                    s.add({"kind": "info", "text": "devtools stopped - send a message to continue this session"})
        self._save()
        for s in live:
            self._terminate(s)

    def wait_state(self, sid: str, states: tuple = ("idle", "stopped", "failed", "asking"), timeout: float = 10.0) -> bool:
        """Test helper: wait until the session is in one of `states`."""
        end = time.time() + timeout
        while time.time() < end:
            with self._lock:
                if self._sessions[sid].state() in states:
                    return True
            time.sleep(0.02)
        return False

    # ---- internals
    def _require_claude(self) -> None:
        if self.claude is None:
            raise ChatError(self.status()["hint"], 503)

    def _find(self, sid: str) -> Session:
        s = self._sessions.get(sid)
        if s is None:
            raise ChatError("chat session not found", 404)
        return s

    @staticmethod
    def _check_text(text: Any) -> str:
        if not isinstance(text, str) or not text.strip():
            raise ChatError("empty message")
        if len(text) > MAX_TEXT:
            raise ChatError("message too long (max %d characters)" % MAX_TEXT)
        return text.strip()

    @staticmethod
    def _check_answers(pending: Dict[str, Any], answers: Any) -> Dict[str, str]:
        questions = [q.get("question") for q in pending["input"].get("questions") or [] if isinstance(q, dict)]
        if not isinstance(answers, dict) or set(answers) != set(questions):
            raise ChatError("answer every question")
        for value in answers.values():
            if not isinstance(value, str) or not value.strip() or len(value) > MAX_TEXT:
                raise ChatError("every answer must be a non-empty text")
        return {q: answers[q].strip() for q in questions}

    def _write(self, s: Session, line: str) -> None:
        try:
            s.proc.stdin.write(line)
            s.proc.stdin.flush()
        except (OSError, ValueError, AttributeError) as exc:
            s.busy = False
            s.error = "cannot write to claude: %s" % exc
            s.add({"kind": "error", "text": s.error})

    def _send(self, s: Session, text: str) -> None:
        if not s.alive():
            self._spawn(s)
        s.add({"kind": "user", "text": text})
        if not s.busy:
            self._turn_started(s)
        s.busy = True
        s.error = ""
        s.used = time.time()
        self._write(s, user_message(text))

    def _spawn(self, s: Session) -> None:
        idle = sorted((o for o in self._sessions.values() if o is not s and o.alive() and o.state() == "idle"),
                      key=lambda o: o.used)  # fmt: skip
        for other in idle[: max(0, len(idle) - MAX_IDLE_PROCESSES + 1)]:
            other.stop_requested = True
            self._terminate(other)
        cmd = build_command(str(self.claude), s.session_id, TASK_MODEL if s.task else "")
        env = dict(os.environ)
        env.pop("CLAUDECODE", None)  # devtools may itself be started from a Claude Code session
        if s.session_id:
            s.add({"kind": "info", "text": "resuming session %s" % s.session_id})
        try:
            proc = self._popen(cmd, cwd=str(self.repo_root), env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1, start_new_session=True)  # fmt: skip
        except OSError as exc:
            raise ChatError("cannot start claude: %s" % exc, 500)
        s.proc = proc
        s.pid = getattr(proc, "pid", None)
        s.stop_requested = False
        s.pending.clear()
        s.cost_base = float(s.cost_usd or 0.0)
        self._requests += 1
        self._write(s, control_request("init_%d" % self._requests, {"subtype": "initialize", "hooks": None}))
        threading.Thread(target=self._read, args=(s, proc), name="chat-%s" % s.id, daemon=True).start()

    def _control(self, s: Session, msg: Dict[str, Any]) -> None:
        """A control protocol message from the CLI (called with `_lock` held)."""
        if msg.get("type") == "control_response":
            response = (msg.get("response") or {}).get("response") or {}
            if isinstance(response.get("commands"), list):
                self.commands = [{"name": str(c.get("name")), "description": str(c.get("description") or ""),
                                  "hint": str(c.get("argumentHint") or "")}
                                 for c in response["commands"] if isinstance(c, dict) and c.get("name")]  # fmt: skip
            return
        request_id, request = str(msg.get("request_id") or ""), msg.get("request") or {}
        if request.get("subtype") == "can_use_tool" and request_id:
            tool = str(request.get("tool_name") or "?")
            inp = request.get("input") if isinstance(request.get("input"), dict) else {}
            rules = [x for x in request.get("permission_suggestions") or [] if isinstance(x, dict) and x.get("type") == "addRules"]
            s.pending[request_id] = {"request_id": request_id, "tool": tool, "input": inp, "suggestions": rules,
                                     "description": str(request.get("description") or ""),
                                     "blocked_path": str(request.get("blocked_path") or "")}  # fmt: skip
            s.add({"kind": "ask", "request_id": request_id, "tool": tool, "input": claude_cli.clip(inp),
                   "text": claude_cli.tool_summary(tool, inp), "always": bool(rules)})  # fmt: skip
        else:  # nothing else is supported: answer so the CLI doesn't wait
            self._write(s, json.dumps({"type": "control_response", "response": {
                "subtype": "error", "request_id": request_id, "error": "not supported by the devtools chat"}}) + "\n")

    def _read(self, s: Session, proc: Any) -> None:
        seen_init = False
        with proc.stdout:
            for line in proc.stdout:
                turn_ended = False
                closed: Optional[Dict[str, Any]] = None  # the calibration sample of the turn that just ended
                for entry in claude_cli.parse_stream_line(line, detail=True):
                    with self._lock:
                        kind = entry["kind"]
                        if kind == "control":
                            self._control(s, entry["msg"])
                            continue
                        if kind == "limits":
                            changed = self.limits is None or self.limits.get("windows") != entry["windows"]
                            self.limits = {"status": entry["status"], "windows": entry["windows"], "updated": time.time()}
                            if changed or time.time() - self._limits_written > 60:  # keeps `updated` fresh
                                self._write_limits()
                            continue
                        if kind == "usage":
                            s.context_tokens = entry["context_tokens"]
                            continue
                        if kind == "task":
                            s.track_task(entry["event"], entry["msg"])
                            continue
                        if entry.get("session_id"):
                            s.session_id = entry["session_id"]
                        if entry.get("init"):  # every turn starts with one - also turns the agent starts itself
                            if not s.busy:
                                self._turn_started(s)
                            s.busy = True
                            if seen_init:
                                continue
                            seen_init = True
                            entry.pop("init")
                        if kind == "result":
                            cost = entry.get("cost_usd")
                            if isinstance(cost, (int, float)):
                                s.cost_usd = round(s.cost_base + cost, 4)
                            s.busy = False
                            s.pending.clear()
                            turn_ended = True
                            closed, s.sample = closed or s.sample, None  # a message sent next opens a new one
                            s.context_window = entry.get("context_window") or s.context_window
                            # a background task's notice may open an empty turn: no second marker for it
                            if entry["is_error"] or not s.log or s.log[-1]["kind"] != "turn":
                                s.add({"kind": "turn", "is_error": entry["is_error"], "cost_usd": s.cost_usd,
                                       "text": entry["text"] if entry["is_error"] else ""})  # fmt: skip
                        else:
                            entry.pop("session_id", None)
                            s.add(entry)
                if turn_ended:
                    self._turn_ended(s, closed)
                    files = self._changed()
                    with self._lock:
                        s.changed_files = files
                    self._save()
                else:
                    self._save(throttle=True)
        code = proc.wait()
        try:
            proc.stdin.close()
        except (OSError, ValueError, RuntimeError, AttributeError):  # a Stop and the reader may close it at once
            pass
        with self._lock:
            if s.proc is proc:
                s.busy = False
                s.pending.clear()
                s.tasks.clear()  # the process took its subagents with it
                s.sample = None
                if s.stop_requested:
                    s.add({"kind": "info", "text": "process stopped - send a message to continue (resumes the session)"})
                elif code != 0:
                    s.error = "claude exited with code %s" % code
                    s.add({"kind": "error", "text": s.error})
        self._save()

    def _windows(self) -> Dict[str, Dict[str, Any]]:
        return dict((self.limits or {}).get("windows") or {})

    def _turn_started(self, s: Session) -> None:
        """Open the calibration sample of a task session's turn; a turn of any session taints the others' samples
        (called with `_lock` held)."""
        if self.calibration_file is None:
            return
        for other in self._sessions.values():
            if other is not s and other.sample is not None:
                other.sample["parallel"] = True
        if not s.task:
            return
        s.sample = {"task": s.task, "chat": s.id, "start": time.time(), "windows": self._windows(),
                    "cost_start": self._cost_so_far(s),
                    "parallel": any(o is not s and o.active() for o in self._sessions.values())}  # fmt: skip

    def _cost_so_far(self, s: Session) -> float:
        """The session's weighted cost at the start of a turn: what the last turn's end read from the transcript, so
        consecutive samples chain; 0 for a new session. Only a session resumed from older history reads its
        transcript here (with `_lock` held - once per session)."""
        if s.weighted_cost is None:
            s.weighted_cost = task_cost.session_cost(self.projects_dir, s.session_id) if s.session_id else 0.0
        return s.weighted_cost

    def _turn_ended(self, s: Session, sample: Optional[Dict[str, Any]]) -> None:
        """Close the turn's sample (taken from the session when its result arrived) and append it to the calibration
        file; the transcript is read without `_lock`."""
        if sample is None or self.calibration_file is None:
            return
        with self._lock:
            session_id = s.session_id
        cost_end = task_cost.session_cost(self.projects_dir, session_id) if session_id else 0.0
        with self._lock:
            now = time.time()
            start, end = sample.pop("windows"), self._windows()
            stale = float((self.limits or {}).get("updated") or 0) < sample["start"]  # no limits during the turn
            windows = {name: {"start": start[name].get("utilization"), "end": end[name].get("utilization"),
                              "resets_start": start[name].get("resets_at"), "resets_end": end[name].get("resets_at")}
                       for name in usage_forecast.WINDOWS if name in start and name in end}  # fmt: skip
            sample.update(start=round(sample["start"], 1), end=round(now, 1), cost_start=round(sample["cost_start"], 4),
                          cost_end=round(cost_end, 4), stale=stale, windows=windows)  # fmt: skip
            s.weighted_cost = cost_end
            sample["parallel"] = sample["parallel"] or any(o is not s and o.active() for o in self._sessions.values())
        try:
            usage_forecast.append_sample(self.calibration_file, sample)
        except OSError as exc:
            print("Cannot write usage calibration %s: %s" % (self.calibration_file, exc), flush=True)

    def _write_limits(self) -> None:
        """The latest windows for the backlog view (called with `_lock` held; a small file)."""
        if self.limits_file is None:
            return
        self._limits_written = time.time()
        try:
            self.limits_file.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.limits_file.with_name(self.limits_file.name + ".tmp")
            tmp.write_text(json.dumps(self.limits), encoding="utf-8")
            os.replace(str(tmp), str(self.limits_file))
        except OSError as exc:
            print("Cannot write %s: %s" % (self.limits_file, exc), flush=True)

    def _kill_if_stuck(self, s: Session, proc: Any) -> None:
        end = time.time() + INTERRUPT_GRACE
        while time.time() < end:
            with self._lock:
                if s.proc is not proc or not s.alive() or not s.busy:
                    return
            time.sleep(0.1)
        with self._lock:
            if s.proc is proc and s.busy:
                s.stop_requested = True
                self._terminate(s)

    def _terminate(self, s: Session) -> None:
        proc = s.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.stdin.close()
        except (OSError, ValueError, RuntimeError, AttributeError):  # a Stop and the reader may close it at once
            pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)  # the agent's own children (godot, tests) too
        except (OSError, AttributeError):
            proc.terminate()

    def _git_status(self) -> List[str]:
        try:
            out = subprocess.run(["git", "status", "--porcelain"], cwd=str(self.repo_root), capture_output=True,
                                 text=True, timeout=20, check=False).stdout  # fmt: skip
        except (OSError, subprocess.SubprocessError):
            return []
        return [line for line in out.splitlines() if line.strip()]

    def _prune(self) -> None:
        old = sorted((s for s in self._sessions.values() if not s.alive()), key=lambda s: s.updated)
        for s in old[: max(0, len(self._sessions) - MAX_SESSIONS)]:
            del self._sessions[s.id]

    def _load(self) -> None:
        if self.state_file is None or not self.state_file.is_file():
            return
        try:
            data = json.loads(self.state_file.read_text(encoding="utf-8"))
            for item in data.get("sessions") or []:
                s = Session.from_dict(item)
                self._sessions[s.id] = s
            self._counter = int(data.get("counter") or len(self._sessions))
            self.limits = data.get("limits") if isinstance(data.get("limits"), dict) else None
            self.commands = [c for c in data.get("commands") or [] if isinstance(c, dict)]
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            print("Ignoring unreadable chat history %s: %s" % (self.state_file, exc), flush=True)

    def _save(self, throttle: bool = False) -> None:
        if self.state_file is None:
            return
        with self._lock:
            if throttle and time.time() - self._saved_at < SAVE_EVERY:
                return
            self._saved_at = time.time()
            data = {"version": 1, "counter": self._counter, "limits": self.limits, "commands": self.commands,
                    "sessions": [s.to_dict() for s in sorted(self._sessions.values(), key=lambda s: s.created)]}  # fmt: skip
            text = json.dumps(data, ensure_ascii=False, indent=1)
        with self._write_lock:
            try:
                self.state_file.parent.mkdir(parents=True, exist_ok=True)
                tmp = self.state_file.with_name("%s.%d.tmp" % (self.state_file.name, threading.get_ident()))
                tmp.write_text(text, encoding="utf-8")
                os.replace(str(tmp), str(self.state_file))
            except OSError as exc:  # history is a convenience: never break a chat over it
                print("Cannot save chat history %s: %s" % (self.state_file, exc), flush=True)
