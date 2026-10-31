#!/usr/bin/env python3
"""Historical Claude Code cost per backlog task, from the session transcripts. Python 3.8, stdlib only.

Usage: tools/task_cost.py [--projects-dir=~/.claude/projects/<repo slug>] [--out=docs/tasks/task_costs.json]

Claude Code writes one transcript per session (`<projects-dir>/<session>.jsonl`, subagents in
`<session>/subagents/**/agent-*.jsonl`); every API response carries its `model` and `usage`. A session belongs to
a task from its `/implement-task <arg>` command on (`/clear` or another `/implement-task` ends that part), and a
subagent belongs to the part its first message falls into. Usage is weighted into one number per task: tokens ×
`WEIGHTS` (API list prices per million tokens of the model family, so the unit reads as "API-equivalent US$").
Several sessions of one task are summed; free chats are ignored. The output holds only task IDs, numbers and model
names - no prompt or message text - and is deterministic (sorted). Claude Code deletes old transcripts
(`cleanupPeriodDays`, 30 days by default), so a re-scan keeps the tasks the file already has: per task the entry
with the higher cost wins (`refresh`), and the file is committed as the record of past tasks.

The weights are shared: devtools (calibration, `session_cost`) and the backlog view import this module.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO_ROOT / "docs" / "tasks" / "task_costs.json"
KINDS = ("input", "cache_write", "cache_read", "output")
USAGE_KEYS = {"input": "input_tokens", "cache_write": "cache_creation_input_tokens",
              "cache_read": "cache_read_input_tokens", "output": "output_tokens"}  # fmt: skip
# US$ per million tokens by model family and token kind (relative API prices; only the ratios matter).
WEIGHTS = {
    "opus": {"input": 5.0, "cache_write": 6.25, "cache_read": 0.5, "output": 25.0},
    "sonnet": {"input": 3.0, "cache_write": 3.75, "cache_read": 0.3, "output": 15.0},
    "haiku": {"input": 1.0, "cache_write": 1.25, "cache_read": 0.1, "output": 5.0},
}
UNKNOWN_FAMILY = "opus"  # weights for a model the table doesn't know (with a warning)
COMMAND = re.compile(r"<command-name>/([\w:-]+)</command-name>.*?<command-args>(.*?)</command-args>", re.S)
PLAIN_COMMAND = re.compile(r"^\s*/(implement-task|clear)\b[ \t]*(\S*)")
TASK_ARG = re.compile(r"^(?:task)?[\s_-]*0*(\d+)([a-z]?)$", re.I)

_warned: Set[str] = set()


def project_dir(repo_root: Path = REPO_ROOT) -> Path:
    """`~/.claude/projects/<slug>`: Claude Code names it after the path, every non-alphanumeric character a `-`."""
    return Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(repo_root).resolve()))


def normalise_task_id(arg: str) -> Optional[str]:
    """`57`, `057`, `TASK 057`, `task-057` → `TASK-057`; `TASK-089b` keeps its suffix; anything else → None."""
    match = TASK_ARG.match(arg.strip().split(" (")[0].strip()) or TASK_ARG.match((arg.split() or [""])[0])
    if not match:
        return None
    return "TASK-%03d%s" % (int(match.group(1)), match.group(2).lower())


def model_family(model: str) -> Optional[str]:
    """`claude-opus-5-5` → `opus`; None for placeholders like `<synthetic>`; unknown names → UNKNOWN_FAMILY."""
    if not model or model.startswith("<"):
        return None
    for family in WEIGHTS:
        if family in model.lower():
            return family
    if model not in _warned:
        _warned.add(model)
        print("task_cost: unknown model %r - weighted like %s" % (model, UNKNOWN_FAMILY), file=sys.stderr)
    return UNKNOWN_FAMILY


def weighted_cost(tokens_by_model: Dict[str, Dict[str, int]]) -> float:
    """Tokens per model and kind → one weighted number (US$-like)."""
    total = 0.0
    for model, tokens in tokens_by_model.items():
        family = model_family(model)
        if family is None:
            continue
        total += sum(tokens.get(kind, 0) * WEIGHTS[family][kind] for kind in KINDS) / 1e6
    return total


def _usage_tokens(usage: Any) -> Dict[str, int]:
    if not isinstance(usage, dict):
        return {}
    return {kind: int(usage.get(key) or 0) for kind, key in USAGE_KEYS.items() if isinstance(usage.get(key) or 0, int)}


def _records(path: Path) -> Iterable[Dict[str, Any]]:
    """The JSON objects of a transcript worth parsing (assistant responses, user commands); malformed lines skipped."""
    try:
        handle = path.open(encoding="utf-8", errors="replace")
    except OSError:
        return
    with handle:
        for line in handle:
            # cheap filter first: tool results and file snapshots are most of the bytes
            if '"assistant"' not in line and "command-name>" not in line and "/implement-task" not in line and "/clear" not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict):
                yield record


def _user_command(record: Dict[str, Any]) -> Optional[Tuple[str, str]]:
    """(`implement-task`|`clear`, argument) of a typed user command, else None."""
    if record.get("type") != "user" or record.get("isSidechain"):
        return None
    content = (record.get("message") or {}).get("content")
    if isinstance(content, list):
        content = " ".join(str(part.get("text") or "") for part in content if isinstance(part, dict) and part.get("type") == "text")
    if not isinstance(content, str):
        return None
    match = COMMAND.search(content) or PLAIN_COMMAND.match(content)
    if not match or match.group(1) not in ("implement-task", "clear"):
        return None
    return match.group(1), match.group(2).strip()


def _assistant_usage(record: Dict[str, Any]) -> Optional[Tuple[str, str, Dict[str, int]]]:
    """(message id, model, tokens) of an API response, else None."""
    if record.get("type") != "assistant":
        return None
    message = record.get("message")
    if not isinstance(message, dict) or not isinstance(message.get("model"), str):
        return None
    tokens = _usage_tokens(message.get("usage"))
    if not tokens:
        return None
    key = message.get("id") or record.get("uuid")
    if not key:
        return None  # can't be deduplicated; real responses always carry an id
    return str(key), message["model"], tokens


class _Part:
    """One task's part of one session."""

    def __init__(self, task: Optional[str], start: str) -> None:
        self.task = task
        self.start = start
        self.end = start
        self.tokens: Dict[str, Dict[str, int]] = {}
        self.main: Dict[str, Dict[str, int]] = {}  # the main session's own responses (the orchestrator)

    def add(self, model: str, tokens: Dict[str, int], timestamp: str, main: bool = False) -> None:
        if main:
            own = self.main.setdefault(model, {kind: 0 for kind in KINDS})
            for kind, value in tokens.items():
                own[kind] += value
        bucket = self.tokens.setdefault(model, {kind: 0 for kind in KINDS})
        for kind, value in tokens.items():
            bucket[kind] += value
        if timestamp and timestamp > self.end:
            self.end = timestamp


def _subagent_files(session_file: Path) -> List[Path]:
    folder = session_file.with_suffix("")
    return sorted(folder.glob("subagents/**/agent-*.jsonl")) if folder.is_dir() else []


def scan_session(session_file: Path, seen: Optional[Set[str]] = None) -> List[_Part]:
    """The task parts of one session (a part with task None is a free chat); subagents included. `seen` (message
    ids already counted) is shared across a scan, so a response copied into another session counts once."""
    parts: List[_Part] = []
    seen = set() if seen is None else seen
    current: Optional[_Part] = None
    for record in _records(session_file):
        timestamp = str(record.get("timestamp") or "")
        command = _user_command(record)
        if command:
            task = normalise_task_id(command[1]) if command[0] == "implement-task" else None
            current = _Part(task, timestamp)
            parts.append(current)
            continue
        usage = _assistant_usage(record)
        if usage is None or usage[0] in seen:
            continue  # one response is written once per content block, with the same usage
        seen.add(usage[0])
        if current is not None:
            current.add(usage[1], usage[2], timestamp, main=not record.get("isSidechain"))
    for sub in _subagent_files(session_file):
        target: Optional[_Part] = None
        for record in _records(sub):
            usage = _assistant_usage(record)
            if usage is None or usage[0] in seen:
                continue
            seen.add(usage[0])
            timestamp = str(record.get("timestamp") or "")
            if target is None:
                started = [p for p in parts if p.start <= timestamp]
                target = started[-1] if started else (parts[0] if parts else None)
                if target is None:
                    break
            target.add(usage[1], usage[2], timestamp)
    return parts


def session_cost(projects_dir: Path, session_id: str) -> float:
    """Weighted cost of one whole session (main agent + subagents) so far; 0 when the transcript is missing."""
    path = Path(projects_dir) / ("%s.jsonl" % session_id)
    if not re.match(r"^[\w-]+$", session_id or "") or not path.is_file():
        return 0.0
    total: Dict[str, Dict[str, int]] = {}
    seen: Set[str] = set()
    for file in [path] + _subagent_files(path):
        for record in _records(file):
            usage = _assistant_usage(record)
            if usage is None or usage[0] in seen:
                continue
            seen.add(usage[0])
            bucket = total.setdefault(usage[1], {kind: 0 for kind in KINDS})
            for kind, value in usage[2].items():
                bucket[kind] += value
    return weighted_cost(total)


def _hours(start: str, end: str) -> float:
    try:
        parse = lambda s: datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")  # noqa: E731
        return max(0.0, (parse(end) - parse(start)).total_seconds() / 3600.0)
    except ValueError:
        return 0.0


def scan(projects_dir: Path) -> Dict[str, Dict[str, Any]]:
    """Task ID → {cost, tokens (per kind), models, sessions, first, last, active_hours, orchestrator (model family
    of the main session's work), main_cost (its share of the cost)}."""
    tasks: Dict[str, Dict[str, Any]] = {}
    seen: Set[str] = set()
    for session_file in sorted(Path(projects_dir).glob("*.jsonl")):
        for part in scan_session(session_file, seen):
            if part.task is None or not part.tokens:
                continue
            entry = tasks.setdefault(part.task, {"by_model": {}, "main": {}, "sessions": set(), "first": part.start, "last": part.end, "active_hours": 0.0})
            for key, source in (("by_model", part.tokens), ("main", part.main)):
                for model, tokens in source.items():
                    bucket = entry[key].setdefault(model, {kind: 0 for kind in KINDS})
                    for kind in KINDS:
                        bucket[kind] += tokens[kind]
            entry["sessions"].add(session_file.stem)
            entry["first"] = min(entry["first"], part.start)
            entry["last"] = max(entry["last"], part.end)
            entry["active_hours"] += _hours(part.start, part.end)
    out: Dict[str, Dict[str, Any]] = {}
    for task in sorted(tasks):
        entry = tasks[task]
        models = sorted(m for m in entry["by_model"] if model_family(m) is not None)
        out[task] = {
            "cost": round(weighted_cost(entry["by_model"]), 4),
            "tokens": {kind: sum(t[kind] for t in entry["by_model"].values()) for kind in KINDS},
            "models": models,
            "sessions": len(entry["sessions"]),
            "first": entry["first"],
            "last": entry["last"],
            "active_hours": round(entry["active_hours"], 2),
            "orchestrator": orchestrator(entry["main"]),
            "main_cost": round(weighted_cost(entry["main"]), 4),
        }
    return out


def orchestrator(main: Dict[str, Dict[str, int]]) -> str:
    """The model family that did most of the main session's (weighted) work; "" without main-session usage."""
    by_family: Dict[str, float] = {}
    for model, tokens in main.items():
        family = model_family(model)
        if family is not None:
            by_family[family] = by_family.get(family, 0.0) + weighted_cost({model: tokens})
    return max(sorted(by_family), key=lambda f: by_family[f]) if by_family else ""


def write(tasks: Dict[str, Dict[str, Any]], out: Path) -> None:
    data = {"version": 1, "unit": "API-equivalent US$ (tokens x WEIGHTS)", "weights": WEIGHTS, "tasks": tasks}
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name("%s.%d.%d.tmp" % (out.name, os.getpid(), threading.get_ident()))  # writers in other processes
    tmp.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(out)


def load(path: Path = DEFAULT_OUT) -> Dict[str, Dict[str, Any]]:
    """The tasks of a written task_costs.json ({} when missing or unreadable)."""
    try:
        tasks = json.loads(Path(path).read_text(encoding="utf-8")).get("tasks") or {}
        return {str(k): v for k, v in tasks.items() if isinstance(v, dict) and isinstance(v.get("cost"), (int, float))}
    except (OSError, ValueError, AttributeError):
        return {}


def merge(old: Dict[str, Dict[str, Any]], new: Dict[str, Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """Per task the entry with the higher cost: a task whose transcripts were cleaned up keeps its old entry."""
    out = dict(old)
    for task, entry in new.items():
        if task not in out or entry.get("cost", 0) >= out[task].get("cost", 0):
            out[task] = entry
    return {task: out[task] for task in sorted(out)}


def refresh(projects_dir: Path, out: Path = DEFAULT_OUT) -> Dict[str, Dict[str, Any]]:
    """Scan the transcripts, merge with what `out` already holds, write it; the merged tasks."""
    tasks = merge(load(out), scan(projects_dir))
    write(tasks, out)
    return tasks


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--projects-dir", type=Path, default=project_dir())
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if not args.projects_dir.is_dir():
        sys.exit("No transcripts in %s" % args.projects_dir)
    tasks = refresh(args.projects_dir, args.out)
    print("%d tasks, %.2f weighted cost in total -> %s" % (len(tasks), sum(t["cost"] for t in tasks.values()), args.out))


if __name__ == "__main__":
    main()
