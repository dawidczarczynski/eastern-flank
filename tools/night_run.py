#!/usr/bin/env python3
"""Unattended night run: implements ready backlog tasks one after another with fresh `claude -p` sessions.

Usage: tools/night_run.py [--until=HH:MM] [--dry-run] [--max-tasks=N] [--task-timeout-min=M]

For every task: `/implement-task TASK-X` (orchestrator on sonnet, auto permission mode like the devtools chat),
then the runner itself runs tools/check.sh. Green -> commit exactly the task's changes (the tree is clean when a
task starts) and push; red -> one fix attempt in the same session, then the changes are saved as a patch in the
run directory and reverted. Waits for the 5-hour window to reset when the CLI reports it is used up; stops when the
weekly window is nearly used up or the deadline passes. At the end it writes docs/NIGHT_REPORT.md (what passed,
what failed, playtest steps of every `to playtest` task) and commits + pushes it.
Run it from the repo root; logs and patches go to ~/night_runs/<timestamp>/. Python 3.8, stdlib only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "docs" / "tasks"

# Priority order: the MVP chain first (each unblocks the next), then independent logic, then visual work.
# A task runs only when `tools/backlog.py --ready` lists it. Design-gated or unrefined tasks are left out on purpose:
# TASK-147, TASK-133 (to refine), TASK-081 (umbrella), the view halves that start with /design-ui (099b, 119b, 107b)
# are handled by the design pass of a later session with the human.
PRIORITY = [
    "TASK-102a", "TASK-102b", "TASK-102c", "TASK-103a", "TASK-103b", "TASK-107a",
    "TASK-099a", "TASK-101", "TASK-119a", "TASK-121", "TASK-081a", "TASK-128",
    "TASK-131b", "TASK-146", "TASK-108h", "TASK-108c", "TASK-108d", "TASK-063",
    "TASK-108g", "TASK-111", "TASK-134", "TASK-135",
]

UNATTENDED = """\
UNATTENDED NIGHT RUN. No human is present and nobody will answer questions.
- Never use AskUserQuestion and never wait for an answer. Where the implement-task skill says to stop and ask the human
  (ambiguous criteria, a failing check after 3 fix attempts, more than 4 agent calls, a design step needing a human
  choice), instead: write the blocker (what you tried, the failing output lines) into the task file's
  "Implementation notes", set the task status back to `ready` in the task file and BACKLOG.md, run
  `tools/backlog.py --fix`, and end the session with a short summary.
- Do NOT commit, push, stash or reset: the runner commits after its own `tools/check.sh`. Do not touch
  docs/tasks/task_costs.json and do not edit other tasks' status except through `tools/backlog.py --fix`.
- Work only on the one task you were given. Follow CLAUDE.md (TDD, architecture rules, `tools/check.sh` before done,
  manual and ADR duties, README screenshot for battle-scene changes).
- Final status: `to playtest` when anything visible to the player changed (and then the task file's
  "Playtest (for the human)" section must be accurate and complete - the human tests it in the morning), otherwise
  `done`. Never claim something looks good that you have not seen.
- Keep the summary short.
"""


def sh(cmd: List[str], **kw: Any) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, **kw)


def log(msg: str) -> None:
    print("[%s] %s" % (dt.datetime.now().strftime("%H:%M:%S"), msg), flush=True)


def ready_ids() -> List[str]:
    out = sh(["python3", "tools/backlog.py", "--ready"]).stdout
    return [line.split("\t")[0] for line in out.splitlines() if line.startswith("TASK-")]


def task_file(task_id: str) -> Optional[Path]:
    found = sorted(TASKS.glob(task_id + "-*.md"))
    return found[0] if found else None


def task_status(task_id: str) -> str:
    f = task_file(task_id)
    if f is None:
        return "?"
    m = re.search(r"^- \*\*Status\*\*:\s*(.+)$", f.read_text(encoding="utf-8"), re.M)
    return re.sub(r"[^\w ]", "", m.group(1)).strip() if m else "?"


def task_model(task_id: str) -> str:
    f = task_file(task_id)
    m = re.search(r"^- \*\*Model\*\*:\s*(\w+)", f.read_text(encoding="utf-8"), re.M) if f else None
    return m.group(1) if m else "sonnet"


def task_title(task_id: str) -> str:
    f = task_file(task_id)
    m = re.search(r"^# (.+)$", f.read_text(encoding="utf-8"), re.M) if f else None
    return m.group(1).strip() if m else task_id


def next_task(attempted: set) -> Optional[str]:
    ready = set(ready_ids())
    for t in PRIORITY:
        if t in ready and t not in attempted:
            return t
    return None


def parse_stream(lines: List[str]) -> Dict[str, Any]:
    """Session id, final result and the last rate-limit windows from a stream-json log."""
    info: Dict[str, Any] = {"session": None, "result": "", "is_error": False, "five": None, "week": None,
                            "five_reset": None, "limited": False}
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("session_id"):
            info["session"] = ev["session_id"]
        if ev.get("type") == "rate_limit_event":
            rl = ev.get("rate_limit_info", {})
            w = rl.get("unifiedWindows", {})
            if "five_hour" in w:
                info["five"] = w["five_hour"].get("utilization")
                info["five_reset"] = w["five_hour"].get("resetsAt")
            if "seven_day" in w:
                info["week"] = w["seven_day"].get("utilization")
            if rl.get("status") not in (None, "allowed", "allowed_warning"):
                info["limited"] = True
        if ev.get("type") == "result":
            info["result"] = str(ev.get("result", ""))
            info["is_error"] = bool(ev.get("is_error"))
            if re.search(r"limit|resets", info["result"], re.I) and info["is_error"]:
                info["limited"] = True
    return info


def run_claude(prompt: str, model: str, logfile: Path, timeout_s: int, resume: Optional[str]) -> Dict[str, Any]:
    cmd = ["claude", "-p", prompt, "--model", model, "--permission-mode", "auto",
           "--output-format", "stream-json", "--verbose", "--append-system-prompt", UNATTENDED]
    if resume:
        cmd += ["--resume", resume]
    lines: List[str] = []
    with logfile.open("a", encoding="utf-8") as fh:
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                start_new_session=True)
        timer = threading.Timer(timeout_s, lambda: os.killpg(proc.pid, signal.SIGKILL))
        timer.start()
        try:
            for line in proc.stdout:  # type: ignore[union-attr]
                fh.write(line)
                lines.append(line)
        finally:
            timer.cancel()
            proc.wait()
    info = parse_stream(lines)
    info["exit"] = proc.returncode
    return info


def wait_for_reset(info: Dict[str, Any], deadline: dt.datetime) -> bool:
    """Sleep until the 5-hour window resets. False when that is past the deadline."""
    reset = info.get("five_reset")
    if not reset:
        wake = dt.datetime.now() + dt.timedelta(minutes=30)
    else:
        wake = dt.datetime.fromtimestamp(float(reset)) + dt.timedelta(minutes=2)
    if wake >= deadline:
        return False
    log("5-hour window used up; sleeping until %s" % wake.strftime("%H:%M"))
    time.sleep(max(60, (wake - dt.datetime.now()).total_seconds()))
    return True


def check_ok() -> Tuple[bool, str]:
    r = sh(["tools/check.sh"], timeout=1800)
    tail = "\n".join((r.stdout + r.stderr).splitlines()[-40:])
    return r.returncode == 0, tail


def revert(task_id: str, run_dir: Path) -> None:
    patch = sh(["git", "diff", "HEAD"]).stdout
    (run_dir / (task_id + ".patch")).write_text(patch, encoding="utf-8")
    untracked = sh(["git", "ls-files", "--others", "--exclude-standard"]).stdout.split("\n")
    (run_dir / (task_id + ".untracked.txt")).write_text("\n".join(untracked), encoding="utf-8")
    sh(["git", "checkout", "--", "."])
    sh(["git", "clean", "-fdq"])


def commit(task_id: str, status: str) -> bool:
    sh(["git", "add", "-A"])
    if sh(["git", "diff", "--cached", "--quiet"]).returncode == 0:
        return False
    msg = "%s (%s, night run)\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" % (task_title(task_id), status)
    r = sh(["git", "commit", "-q", "-m", msg])
    if r.returncode != 0:
        log("commit failed: " + r.stderr.strip())
        return False
    p = sh(["git", "push", "-q"])
    if p.returncode != 0:
        log("push failed (kept locally): " + p.stderr.strip())
    return True


def run_task(task_id: str, run_dir: Path, deadline: dt.datetime, timeout_min: int) -> Dict[str, Any]:
    logfile = run_dir / (task_id + ".jsonl")
    res: Dict[str, Any] = {"task": task_id, "outcome": "failed", "status": "", "note": ""}
    prompt = "/implement-task " + task_id
    session: Optional[str] = None
    info: Dict[str, Any] = {}
    for attempt in range(4):
        info = run_claude(prompt, "sonnet", logfile, timeout_min * 60, session)
        session = info.get("session") or session
        if info.get("week") is not None and info["week"] >= 0.97:
            res["note"] = "weekly window nearly used up"
            res["outcome"] = "stopped"
            return res
        if info.get("limited") and task_status(task_id) in ("in progress", "ready", "?"):
            if not wait_for_reset(info, deadline):
                res["note"] = "limit reached, reset after the deadline"
                res["outcome"] = "stopped"
                return res
            prompt = "Continue the task where you stopped (the usage limit has reset)."
            continue
        break
    status = task_status(task_id)
    res["status"] = status
    if status not in ("to playtest", "done"):
        res["note"] = "session ended with status '%s': %s" % (status, info.get("result", "")[:300])
        revert(task_id, run_dir)
        sh(["python3", "tools/backlog.py", "--fix"])
        return res
    ok, tail = check_ok()
    if not ok and session:
        log("%s: check failed, one fix attempt" % task_id)
        info = run_claude("tools/check.sh failed after your work. Fix it (do not commit). Output tail:\n" + tail,
                          "sonnet", logfile, timeout_min * 60, session)
        ok, tail = check_ok()
    if not ok:
        res["note"] = "tools/check.sh failed: " + tail[-600:]
        revert(task_id, run_dir)
        sh(["python3", "tools/backlog.py", "--fix"])
        return res
    sh(["python3", "tools/backlog.py", "--fix"])
    commit(task_id, status)
    res["outcome"] = "ok"
    return res


def playtest_steps(task_id: str) -> str:
    f = task_file(task_id)
    if f is None:
        return ""
    m = re.search(r"^## Playtest.*?\n(.*?)(?=^## |\Z)", f.read_text(encoding="utf-8"), re.M | re.S)
    return m.group(1).strip() if m else ""


def write_report(results: List[Dict[str, Any]], started: dt.datetime, run_dir: Path) -> None:
    lines = ["# Night run report", "",
             "Run %s - %s (logs and patches of failed tasks: `%s`)." % (
                 started.strftime("%Y-%m-%d %H:%M"), dt.datetime.now().strftime("%H:%M"), run_dir), "",
             "| Task | Result | Status | Note |", "|---|---|---|---|"]
    for r in results:
        lines.append("| %s | %s | %s | %s |" % (r["task"], r["outcome"], r["status"], r["note"].replace("\n", " ")[:240]))
    lines += ["", "## To playtest", ""]
    shown = False
    for r in results:
        if r["outcome"] == "ok" and r["status"] == "to playtest":
            shown = True
            lines += ["### %s" % task_title(r["task"]), "", playtest_steps(r["task"]) or "_see the task file_", ""]
    if not shown:
        lines.append("_nothing_")
    (ROOT / "docs" / "NIGHT_REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--until", default="03:45")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--max-tasks", type=int, default=99)
    ap.add_argument("--task-timeout-min", type=int, default=110)
    args = ap.parse_args()
    h, m = (int(x) for x in args.until.split(":"))
    now = dt.datetime.now()
    deadline = now.replace(hour=h, minute=m, second=0, microsecond=0)
    if deadline <= now:
        deadline += dt.timedelta(days=1)
    if args.dry_run:
        ready = set(ready_ids())
        for t in PRIORITY:
            print("%-10s %-8s %-7s %s" % (t, "READY" if t in ready else "blocked", task_model(t), task_title(t)[:70]))
        return 0
    if sh(["git", "diff", "--quiet", "HEAD"]).returncode != 0 or sh(["git", "ls-files", "--others", "--exclude-standard"]).stdout.strip():
        print("Working tree is not clean - commit or stash first.", file=sys.stderr)
        return 2
    run_dir = Path.home() / "night_runs" / now.strftime("%Y%m%d_%H%M")
    run_dir.mkdir(parents=True, exist_ok=True)
    sh(["git", "tag", "-f", "pre-night"])
    log("start, deadline %s, logs in %s" % (deadline.strftime("%H:%M"), run_dir))
    results: List[Dict[str, Any]] = []
    attempted: set = set()
    while len(results) < args.max_tasks and dt.datetime.now() < deadline - dt.timedelta(minutes=20):
        t = next_task(attempted)
        if t is None:
            log("no more ready tasks in the queue")
            break
        attempted.add(t)
        log("== %s (%s) %s" % (t, task_model(t), task_title(t)[:80]))
        r = run_task(t, run_dir, deadline, args.task_timeout_min)
        log("%s -> %s %s %s" % (t, r["outcome"], r["status"], r["note"][:120]))
        results.append(r)
        write_report(results, now, run_dir)
        if r["outcome"] == "stopped":
            break
    write_report(results, now, run_dir)
    sh(["python3", "tools/task_cost.py"])
    sh(["git", "add", "docs/NIGHT_REPORT.md"])
    sh(["git", "commit", "-q", "-m", "Night run report\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"])
    sh(["git", "add", "docs/tasks/task_costs.json"])
    sh(["git", "commit", "-q", "-m", "Task costs after the night run\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"])
    sh(["git", "push", "-q"])
    log("done: %d tasks" % len(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
