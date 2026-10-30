"""Child processes of the devtools hub: supervised web tools and command jobs. Python 3.8, stdlib only."""
from __future__ import annotations

import glob
import os
import re
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.request import urlopen

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MAX_LINES = 5000  # output lines kept per job
MAX_JOBS = 30  # finished jobs kept


def _stop(proc: "subprocess.Popen[bytes]", timeout: float = 5.0) -> None:
    """SIGTERM to the whole process group (the tools are shell scripts starting Godot), then SIGKILL."""
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
    except ProcessLookupError:
        pass


class Service:
    """A web tool on a fixed port: reused when something already answers there, otherwise started by the hub."""

    def __init__(self, spec: Dict[str, Any], repo_root: Path, log_dir: Path) -> None:
        self.spec = spec
        self.repo_root = repo_root
        self.log_path = log_dir / ("%s.log" % spec["id"])
        self.proc: Optional["subprocess.Popen[bytes]"] = None
        self.lock = threading.Lock()

    def alive(self) -> bool:
        try:
            with urlopen("http://127.0.0.1:%d%s" % (self.spec["port"], self.spec["probe"]), timeout=1):
                return True
        except OSError:
            return False

    def status(self) -> Dict[str, Any]:
        managed = self.proc is not None and self.proc.poll() is None
        info = {k: self.spec[k] for k in ("id", "label", "description", "port")}
        info.update(up=self.alive(), managed=managed)
        if self.proc is not None and self.proc.poll() is not None:
            info["exit_code"] = self.proc.returncode
        return info

    def start(self) -> None:
        with self.lock:
            if (self.proc is not None and self.proc.poll() is None) or self.alive():
                return
            self.log_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.log_path, "ab") as log:
                self.proc = subprocess.Popen(self.spec["argv"], cwd=self.repo_root, stdout=log, stderr=subprocess.STDOUT,
                                             stdin=subprocess.DEVNULL, start_new_session=True)

    def wait_up(self, timeout: float = 10.0) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.alive():
                return True
            if self.proc is not None and self.proc.poll() is not None:
                return False
            time.sleep(0.1)
        return False

    def stop(self) -> None:
        with self.lock:
            if self.proc is not None:
                _stop(self.proc)

    def log_tail(self, lines: int = 40) -> str:
        try:
            return "\n".join(self.log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-lines:])
        except OSError:
            return ""


class Job:
    def __init__(self, job_id: str, command: Dict[str, Any], params: Dict[str, Any], argv: List[str],
                 env: Dict[str, str], images: List[str]) -> None:
        self.id = job_id
        self.command_id = command["id"]
        self.label = command["label"]
        self.exclusive = command.get("exclusive", True)
        self.params = params
        self.argv = argv
        self.env = env
        self.image_patterns = images
        self.state = "queued"  # queued → running → ok / failed / cancelled
        self.exit_code: Optional[int] = None
        self.lines: List[str] = []
        self.dropped = 0  # lines dropped from the front (MAX_LINES)
        self.created = time.time()
        self.started: Optional[float] = None
        self.finished: Optional[float] = None
        self.proc: Optional["subprocess.Popen[bytes]"] = None
        self.cancel_requested = False

    def summary(self) -> Dict[str, Any]:
        return {
            "id": self.id, "command": self.command_id, "label": self.label, "params": self.params,
            "argv": self.argv, "state": self.state, "exit_code": self.exit_code, "created": self.created,
            "started": self.started, "finished": self.finished,
        }


class JobRunner:
    """Runs command jobs. Exclusive jobs (Godot runs, tests) wait for each other; the others start at once."""

    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root
        self.jobs: List[Job] = []
        self.lock = threading.Condition()
        self.counter = 0
        self.closed = False

    def submit(self, command: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
        argv = command["argv"](params)
        env = command["env"](params) if "env" in command else {}
        images = command["images"](params) if "images" in command else []
        with self.lock:
            self.counter += 1
            job = Job("%d" % self.counter, command, params, argv, env, images)
            self.jobs.append(job)
            finished = [j for j in self.jobs if j.finished is not None]
            for old in finished[: max(0, len(finished) - MAX_JOBS)]:
                self.jobs.remove(old)
        threading.Thread(target=self._run, args=(job,), daemon=True).start()
        return job.summary()

    def list(self) -> List[Dict[str, Any]]:
        with self.lock:
            return [job.summary() for job in reversed(self.jobs)]

    def _find(self, job_id: str) -> Optional[Job]:
        return next((j for j in self.jobs if j.id == job_id), None)

    def get(self, job_id: str, since: int = 0) -> Optional[Dict[str, Any]]:
        with self.lock:
            job = self._find(job_id)
            if job is None:
                return None
            start = max(0, since - job.dropped)
            info = job.summary()
            info.update(lines=job.lines[start:], next=job.dropped + len(job.lines), images=self._images(job))
            return info

    def cancel(self, job_id: str) -> bool:
        with self.lock:
            job = self._find(job_id)
            if job is None or job.finished is not None:
                return False
            job.cancel_requested = True
            proc = job.proc
            self.lock.notify_all()
        if proc is not None:
            _stop(proc)
        return True

    def shutdown(self) -> None:
        with self.lock:
            self.closed = True
            running = [j for j in self.jobs if j.finished is None]
        for job in running:
            self.cancel(job.id)

    def _images(self, job: Job) -> List[str]:
        """Image files the job wrote (newer than its start), as repo-relative paths."""
        if job.state != "ok" or job.started is None:
            return []
        found = []
        for pattern in job.image_patterns:
            for path in sorted(glob.glob(str(self.repo_root / pattern))):
                if os.path.getmtime(path) >= job.started - 1:
                    found.append(str(Path(path).relative_to(self.repo_root)))
        return found

    def _add(self, job: Job, line: str) -> None:
        with self.lock:
            job.lines.append(line)
            if len(job.lines) > MAX_LINES:
                del job.lines[0]
                job.dropped += 1

    def _blocked(self, job: Job) -> bool:
        """An exclusive job waits while an exclusive job runs or an earlier one is still queued (FIFO)."""
        return job.exclusive and any(
            j.exclusive and (j.state == "running" or (j.state == "queued" and int(j.id) < int(job.id)))
            for j in self.jobs if j is not job
        )

    def _run(self, job: Job) -> None:
        with self.lock:
            while self._blocked(job) and not job.cancel_requested and not self.closed:
                self.lock.wait(0.5)
            if job.cancel_requested or self.closed:
                job.state, job.finished = "cancelled", time.time()
                self.lock.notify_all()
                return
            job.state, job.started = "running", time.time()
            env = dict(os.environ, **job.env)
            try:
                job.proc = subprocess.Popen(job.argv, cwd=self.repo_root, env=env, stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
            except OSError as exc:
                job.lines.append("cannot start %s: %s" % (job.argv[0], exc))
                job.state, job.finished = "failed", time.time()
                self.lock.notify_all()
                return
        assert job.proc.stdout is not None
        for raw in job.proc.stdout:
            self._add(job, ANSI.sub("", raw.decode("utf-8", errors="replace").rstrip("\r\n")))
        code = job.proc.wait()
        with self.lock:
            job.exit_code = code
            job.finished = time.time()
            job.state = "cancelled" if job.cancel_requested else ("ok" if code == 0 else "failed")
            self.lock.notify_all()
