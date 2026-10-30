"""Claude chat of the devtools hub: Claude Code sessions the human talks to in the browser. Python 3.8, stdlib only.

A session is one `claude -p --input-format stream-json --output-format stream-json` process: every message the
human sends goes to its stdin as a stream-json user message, so the agent keeps its context between turns.
A session started from the backlog opens with the fixed prompt `/implement-task <TASK-ID>`; a free chat opens
with the human's text. When the process is gone (Stop, a devtools restart, a crash) the next message starts a new
one with `--resume <session id>`.

Permissions (ADR 0017): every process runs in Claude Code's `auto` permission mode with `--permission-prompts none`.
A classifier approves safe actions and blocks risky ones (data exfiltration, destructive commands, …); nobody can
answer a prompt, so a blocked action is denied and the agent tells the human what it needs. A pre-approved
allow-list (repository edits, the project's `tools/` scripts, read-only git, web, skills, subagents) skips the
classifier; a deny-list wins over both: no commit, push, reset, clean, rebase or stash, no edits in `.git/`,
`.godot/` or `*.import`.

One session works at a time (sessions and unit catalog jobs share the working tree), and only one Claude process
stays alive: starting one stops the idle process of any other session (it resumes on its next message).
History is saved to `.devtools/chats.json` (git-ignored).
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

CLAUDE_ENV = "DEVTOOLS_CLAUDE"
TASK_RE = re.compile(r"^TASK-\d+[a-z]?$")
MAX_TEXT = 32 * 1024  # characters per message
MAX_LOG = 4000  # log entries kept per session
PERSIST_LOG = 1500  # log entries per session written to the state file
MAX_SESSIONS = 40
SAVE_EVERY = 2.0  # seconds between state file writes while a session streams
CLOSED_STATUSES = ("done", "merged", "idea")  # tasks the backlog button does not implement
BASH_ALLOWED = (
    "tools/check.sh", "tools/test.sh", "tools/lint.sh", "tools/backlog.py", "python3 tools/backlog.py",
    "tools/screenshot.sh", "tools/readme_screenshot.sh", "tools/render_unit.sh", "tools/simulate.sh",
    "godot --headless", "git status", "git diff", "git log", "git show",
)  # fmt: skip
GIT_DENIED = ("commit", "push", "reset", "clean", "rebase", "stash")  # history and the human's uncommitted work
SYSTEM_PROMPT = (
    "You run headless inside the Eastern Flank devtools chat (tools/devtools.sh). The human reads your messages in "
    "a browser and replies there. Your permission mode is auto: a classifier blocks risky actions and nobody can "
    "answer a permission prompt - if an action you need is denied, say exactly what the human should run and wait. "
    "When you need a decision, "
    "ask it at the end of your message and end your turn. Never commit or push; the human does that."
)


class ChatError(Exception):
    def __init__(self, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.status = status


def find_claude() -> Optional[str]:
    """Path of the `claude` CLI: $DEVTOOLS_CLAUDE, then PATH, then the binary bundled with the VS Code extension."""
    return claude_cli.find_claude(CLAUDE_ENV)


def permissions(repo_root: Path) -> Dict[str, List[str]]:
    """The pre-approved allow-list and the deny-list of every chat process (everything else goes to the auto mode
    classifier). File rules are absolute (`//abs/path`): a `cd` in the agent's shell moves the directory relative
    rules are resolved against. `Edit(...)` covers every file-writing tool; deny rules win over everything."""
    base = "/" + str(Path(repo_root).resolve()).rstrip("/")
    allow = ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "Skill", "Agent", "SendMessage", "TodoWrite",
             "Edit(%s/**)" % base] + ["Bash(%s:*)" % cmd for cmd in BASH_ALLOWED]  # fmt: skip
    deny = ["Edit(%s/.git/**)" % base, "Edit(%s/.godot/**)" % base, "Edit(%s/**/*.import)" % base, "AskUserQuestion"]
    deny += ["Bash(git %s:*)" % cmd for cmd in GIT_DENIED]
    return {"allow": allow, "deny": deny}


def lock_history(state_file: Path) -> Optional[Any]:
    """Hold `<state_file>.lock` for the life of the process (an open file with an flock), or None when another
    devtools instance holds it: two hubs would overwrite each other's history and miss each other's working chat."""
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


def build_command(claude: str, repo_root: Path, resume: str = "") -> List[str]:
    """argv of one chat process (no shell). Messages, the first prompt too, arrive on stdin."""
    perms = permissions(repo_root)
    cmd = [claude, "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
           "--permission-mode", "auto", "--permission-prompts", "none", "--append-system-prompt", SYSTEM_PROMPT,
           "--allowedTools", ",".join(perms["allow"]), "--disallowedTools", ",".join(perms["deny"])]  # fmt: skip
    if resume:
        if not claude_cli.SESSION_RE.match(resume):
            raise ChatError("not a Claude Code session id")
        cmd += ["--resume", resume]
    return cmd


def user_message(text: str) -> str:
    return json.dumps({"type": "user", "message": {"role": "user", "content": text}}, ensure_ascii=False) + "\n"


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
        self.stop_requested = False

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def state(self) -> str:
        if self.alive():
            return "working" if self.busy else "idle"
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
                "context_window": self.context_window}  # fmt: skip

    def detail(self, since: int = 0) -> Dict[str, Any]:
        start = max(0, since - self.log_offset)
        out = self.summary()
        out.update(log=self.log[start:], log_from=self.log_offset + start, changed_files=self.changed_files,
                   resume_command="claude --resume %s" % self.session_id if self.session_id else "")  # fmt: skip
        return out

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
Probe = Callable[[], Optional[str]]


class ChatManager:
    """Claude sessions of the hub. `popen`, `busy_probe` (another tool's running agent, as a message) and
    `changed` (`git status` lines) are injectable for tests."""

    def __init__(self, repo_root: Path, claude: Optional[str], popen: Popen = subprocess.Popen,
                 state_file: Optional[Path] = None, busy_probe: Optional[Probe] = None,
                 changed: Optional[Callable[[], List[str]]] = None, unavailable: str = "") -> None:  # fmt: skip
        self.repo_root = Path(repo_root)
        self.claude = None if unavailable else claude
        self._unavailable = unavailable  # why the chat is off although the CLI may exist
        self.state_file = Path(state_file) if state_file else None
        self._popen = popen
        self._busy_probe = busy_probe
        self._changed = changed or self._git_status
        self._sessions: Dict[str, Session] = {}
        self._lock = threading.RLock()
        self._write_lock = threading.Lock()  # the state file is written outside `_lock`
        self._counter = 0
        self._saved_at = 0.0
        self.limits: Optional[Dict[str, Any]] = None  # the subscription's usage windows, as last reported by the CLI
        self._load()

    # ---- API used by the server
    def status(self) -> Dict[str, Any]:
        return {"available": self.claude is not None, "claude": self.claude or "",
                "hint": "" if self.claude else self._unavailable or "Claude Code CLI not found: install it (`claude` on "
                "PATH) or set %s to its path, log in once with `claude`, then restart devtools." % CLAUDE_ENV,
                "permissions": permissions(self.repo_root), "limits": self.limits}  # fmt: skip

    def list(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [s.summary() for s in sorted(self._sessions.values(), key=lambda s: s.updated, reverse=True)]

    def get(self, sid: str, since: int = 0) -> Dict[str, Any]:
        with self._lock:
            return self._find(sid).detail(since)

    def busy(self) -> Optional[str]:
        """What is working right now (for other tools' lock), or None."""
        with self._lock:
            for s in self._sessions.values():
                if s.state() == "working":
                    return "the devtools Claude chat is working on %s" % (s.task or "\"%s\"" % s.title)
        return None

    def create(self, task: Any = None, text: Any = None) -> Dict[str, Any]:
        """A new session: `task` → `/implement-task <task>` (an open session of that task is returned instead),
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
            self._check_free(None)
            self._counter += 1
            s = Session("%s-%d" % (time.strftime("%m%d%H%M%S"), self._counter), title, task or "")
            self._sessions[s.id] = s
            self._prune()
            self._send(s, prompt)
            out = s.summary()
        self._save()
        return out

    def send(self, sid: str, text: Any) -> Dict[str, Any]:
        self._require_claude()
        text = self._check_text(text)
        with self._lock:
            s = self._find(sid)
            if s.busy and s.alive():
                raise ChatError("Claude is still working on the last message - wait for it or press Stop", 409)
            self._check_free(s)
            self._send(s, text)
            out = s.summary()
        self._save()
        return out

    def stop(self, sid: str) -> Dict[str, Any]:
        with self._lock:
            s = self._find(sid)
            if s.alive():
                s.stop_requested = True
                self._terminate(s)
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

    def wait_idle(self, sid: str, timeout: float = 10.0) -> bool:
        """Test helper: wait until the session's turn ended."""
        end = time.time() + timeout
        while time.time() < end:
            with self._lock:
                if self._sessions[sid].state() != "working":
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

    def _check_free(self, me: Optional[Session]) -> None:
        """One working session at a time, and none while another tool's agent edits the tree."""
        for s in self._sessions.values():
            if s is not me and s.state() == "working":
                raise ChatError("another chat is working (%s) - wait for it or stop it first" % (s.task or s.title), 409)
        if me is not None and not me.alive() and claude_cli.agent_alive(me.pid):
            raise ChatError("the old Claude process of this chat (pid %d) is still running - stop it first" % me.pid, 409)
        message = self._busy_probe() if self._busy_probe else None
        if message:
            raise ChatError(message + " - wait until it ends (shared working tree)", 409)

    def _send(self, s: Session, text: str) -> None:
        if not s.alive():
            self._spawn(s)
        s.add({"kind": "user", "text": text})
        s.busy = True
        s.error = ""
        try:
            s.proc.stdin.write(user_message(text))
            s.proc.stdin.flush()
        except (OSError, ValueError) as exc:
            s.busy = False
            s.error = "cannot send to claude: %s" % exc
            s.add({"kind": "error", "text": s.error})

    def _spawn(self, s: Session) -> None:
        for other in self._sessions.values():  # keep a single Claude process alive
            if other is not s and other.alive():
                other.stop_requested = True
                self._terminate(other)
        cmd = build_command(str(self.claude), self.repo_root, s.session_id)
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
        s.cost_base = float(s.cost_usd or 0.0)
        threading.Thread(target=self._read, args=(s, proc), name="chat-%s" % s.id, daemon=True).start()

    def _read(self, s: Session, proc: Any) -> None:
        seen_init = False
        with proc.stdout:
            for line in proc.stdout:
                turn_ended = False
                for entry in claude_cli.parse_stream_line(line):
                    with self._lock:
                        if entry["kind"] == "limits":
                            self.limits = {"status": entry["status"], "windows": entry["windows"], "updated": time.time()}
                            continue
                        if entry["kind"] == "usage":
                            s.context_tokens = entry["context_tokens"]
                            continue
                        if entry.get("session_id"):
                            s.session_id = entry["session_id"]
                        if entry.get("init"):
                            if seen_init:
                                continue
                            seen_init = True
                            entry.pop("init")
                        if entry["kind"] == "result":
                            cost = entry.get("cost_usd")
                            if isinstance(cost, (int, float)):
                                s.cost_usd = round(s.cost_base + cost, 4)
                            s.busy = False
                            turn_ended = True
                            s.context_window = entry.get("context_window") or s.context_window
                            s.add({"kind": "turn", "is_error": entry["is_error"], "cost_usd": s.cost_usd,
                                   "text": entry["text"] if entry["is_error"] else ""})  # fmt: skip
                        else:
                            entry.pop("session_id", None)
                            s.add(entry)
                if turn_ended:
                    files = self._changed()
                    with self._lock:
                        s.changed_files = files
                    self._save()
                else:
                    self._save(throttle=True)
        code = proc.wait()
        try:
            proc.stdin.close()
        except (OSError, ValueError, RuntimeError, AttributeError):  # Stop and the reader may close it at once
            pass
        with self._lock:
            if s.proc is proc:
                s.busy = False
                if s.stop_requested:
                    s.add({"kind": "info", "text": "stopped - send a message to continue (resumes the session)"})
                elif code != 0:
                    s.error = "claude exited with code %s" % code
                    s.add({"kind": "error", "text": s.error})
        self._save()

    def _terminate(self, s: Session) -> None:
        proc = s.proc
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.stdin.close()
        except (OSError, ValueError, RuntimeError, AttributeError):  # Stop and the reader may close it at once
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
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            print("Ignoring unreadable chat history %s: %s" % (self.state_file, exc), flush=True)

    def _save(self, throttle: bool = False) -> None:
        if self.state_file is None:
            return
        with self._lock:
            if throttle and time.time() - self._saved_at < SAVE_EVERY:
                return
            self._saved_at = time.time()
            data = {"version": 1, "counter": self._counter, "limits": self.limits,
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
