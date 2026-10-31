#!/usr/bin/env python3
"""Devtools hub (tools/devtools.sh): one page for every dev tool. Python 3.8, stdlib only.

Starts the web tools (backlog viewer, unit catalog) as child processes – or reuses ones already running –
and shows them as tabs; runs the command-line tools (check, tests, simulation, screenshots, render, game)
as jobs with live output and the images they wrote; hosts the Claude chat (chat.py, ADR 0017). Binds to
127.0.0.1 only; foreign Host headers are refused, and POSTs need a JSON content type and a same-origin Origin.
"""
from __future__ import annotations

import argparse
import json
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qs, unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
import chat  # noqa: E402
import registry  # noqa: E402
import runner  # noqa: E402
import static  # noqa: E402
import task_cost  # noqa: E402  (tools/task_cost.py, on the path via chat)

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
LOG_DIR = registry.REPO_ROOT / ".devtools"  # service logs, git-ignored
CALIBRATION_FILE = registry.REPO_ROOT / "docs" / "tasks" / "usage_calibration.jsonl"  # TASK-109 usage samples
IMAGE_DIRS = (".screenshots/", "docs/images/")  # the only places /files/ serves images from
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
}
MAX_BODY = 64 * 1024


class Handler(BaseHTTPRequestHandler):
    server_version = "Devtools/1"
    repo_root: Path = registry.REPO_ROOT
    services: Dict[str, runner.Service] = {}
    jobs: Any = None  # runner.JobRunner
    chat: Any = None  # chat.ChatManager

    def log_message(self, fmt: str, *args: Any) -> None:  # keep the console quiet
        pass

    def _send(self, status: int, body: bytes, ctype: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data: Any, status: int = 200) -> None:
        self._send(status, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _image(self, rel: str) -> None:
        path = (self.repo_root / rel).resolve()
        allowed = any(str(path).startswith(str((self.repo_root / d).resolve()) + "/") for d in IMAGE_DIRS)
        if not allowed or path.suffix.lower() != ".png" or not path.is_file():
            self._json({"error": "not found"}, 404)
            return
        self._send(200, path.read_bytes(), "image/png")

    def _host_ok(self) -> bool:
        """Reject foreign Host headers (DNS rebinding protection)."""
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
        return host in ("localhost", "127.0.0.1", "")

    def _csrf_ok(self) -> bool:
        """POSTs need a JSON content type and, if sent, this page's Origin (another site can't start a job or a chat)."""
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/json":
            return False
        origin = self.headers.get("Origin")
        port = self.server.server_address[1]
        return origin is None or origin in ("http://localhost:%d" % port, "http://127.0.0.1:%d" % port)

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
        if not self._host_ok():
            self._json({"error": "forbidden host"}, 403)
            return
        url = urlsplit(self.path)
        path = unquote(url.path)
        query = parse_qs(url.query)
        if path in STATIC:
            name, ctype = STATIC[path]
            self._send(200, (HERE / name).read_bytes(), ctype)
        elif path == "/api/services":
            self._json([s.status() for s in self.services.values()])
        elif path.startswith("/api/services/") and path.endswith("/log"):
            service = self.services.get(path[len("/api/services/") : -len("/log")])
            self._json({"log": service.log_tail()} if service else {"error": "unknown service"}, 200 if service else 404)
        elif path == "/api/commands":
            self._json(registry.describe())
        elif path == "/api/jobs":
            self._json(self.jobs.list())
        elif path.startswith("/api/jobs/"):
            since = int(query.get("since", ["0"])[0] or 0)
            job = self.jobs.get(path[len("/api/jobs/") :], since)
            self._json(job if job else {"error": "unknown job"}, 200 if job else 404)
        elif path == "/api/chat":
            self._json(dict(self.chat.status(), sessions=self.chat.list()))
        elif path.startswith("/api/chat/"):
            since = query.get("since", ["0"])[0]
            try:
                self._json(self.chat.get(path[len("/api/chat/") :], int(since) if since.isdigit() else 0))
            except chat.ChatError as exc:
                self._json({"error": exc.message}, exc.status)
        elif path.startswith("/files/"):
            self._image(path[len("/files/") :])
        elif path == "/theme.css":
            self._send(200, static.THEME.read_bytes(), "text/css; charset=utf-8")
        elif path.startswith("/fonts/") and static.font(path[len("/fonts/") :]):
            self._send(200, static.font(path[len("/fonts/") :]).read_bytes(), "font/ttf")
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802 (http.server API)
        if not self._host_ok() or not self._csrf_ok():
            self._json({"error": "POST needs Content-Type: application/json and a localhost Origin"}, 403)
            return
        path = unquote(urlsplit(self.path).path)
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            self._json({"error": "request too large"}, 413)
            return
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self._json({"error": "invalid JSON"}, 400)
            return
        if not isinstance(body, dict):
            self._json({"error": "body must be a JSON object"}, 400)
            return
        parts = path.strip("/").split("/")  # api, <kind>, <id>, [action]
        if parts[:2] == ["api", "chat"]:
            self._chat_post(parts[2:], body)
        elif parts[:2] == ["api", "jobs"] and len(parts) == 2:
            command = registry.find(str(body.get("command", "")))
            if command is None:
                self._json({"error": "unknown command"}, 404)
                return
            try:
                params = registry.validate(command, body.get("params", {}))
            except registry.ParamError as exc:
                self._json({"error": str(exc)}, 400)
                return
            self._json(self.jobs.submit(command, params), 201)
        elif parts[:2] == ["api", "jobs"] and len(parts) == 4 and parts[3] == "cancel":
            self._json({"cancelled": self.jobs.cancel(parts[2])})
        elif parts[:2] == ["api", "services"] and len(parts) == 4 and parts[3] in ("start", "stop", "restart"):
            service = self.services.get(parts[2])
            if service is None:
                self._json({"error": "unknown service"}, 404)
                return
            if parts[3] in ("stop", "restart"):
                service.stop()
            if parts[3] in ("start", "restart"):
                service.start()
                service.wait_up()
            self._json(service.status())
        else:
            self._json({"error": "not found"}, 404)


    def _chat_post(self, parts: List[str], body: Dict[str, Any]) -> None:
        try:
            if not parts:
                if body.get("task") is not None:
                    out = self.chat.create(task=body.get("task"), design=body.get("design") is True)
                else:
                    out = self.chat.create(text=body.get("text"))
                self._json(out, 200 if out.get("existing") else 201)
            elif len(parts) == 2 and parts[1] == "send":
                self._json(self.chat.send(parts[0], body.get("text")))
            elif len(parts) == 2 and parts[1] == "answer":
                self._json(self.chat.answer(parts[0], body.get("request_id"), body.get("behavior"), body.get("answers"),
                                            body.get("message", "")))  # fmt: skip
            elif len(parts) == 2 and parts[1] == "stop":
                self._json(self.chat.stop(parts[0]))
            else:
                self._json({"error": "not found"}, 404)
        except chat.ChatError as exc:
            self._json({"error": exc.message}, exc.status)
        except Exception as exc:  # pragma: no cover - answer instead of dropping the connection
            self._json({"error": "internal error: %s" % exc}, 500)


def make_handler(repo_root: Path, services: Dict[str, runner.Service], jobs: runner.JobRunner,
                 chats: Optional[chat.ChatManager] = None) -> type:
    chats = chats or chat.ChatManager(repo_root, None)
    return type("DevtoolsHandler", (Handler,), {"repo_root": repo_root, "services": services, "jobs": jobs, "chat": chats})


def _scan_task_costs() -> None:
    """Refresh docs/tasks/task_costs.json for the backlog view's Usage column (a few seconds of transcript reading)."""
    projects = task_cost.project_dir(registry.REPO_ROOT)
    if not projects.is_dir():
        return
    try:
        task_cost.refresh(projects)
    except Exception as exc:  # noqa: BLE001 (a background convenience: report, never kill devtools)
        print("Cannot refresh task costs: %s" % exc, flush=True)


def _raise_interrupt(*_: Any) -> None:
    raise KeyboardInterrupt


def main(argv: Optional[List[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8760)
    args = parser.parse_args(argv)
    services = {spec["id"]: runner.Service(spec, registry.REPO_ROOT, LOG_DIR) for spec in registry.SERVICES}
    jobs = runner.JobRunner(registry.REPO_ROOT)
    history = LOG_DIR / "chats.json"
    history_lock = chat.lock_history(history)  # noqa: F841 (held until the process exits)
    chats = chat.ChatManager(registry.REPO_ROOT, chat.find_claude(), state_file=history if history_lock else None,
                             unavailable="" if history_lock else "another devtools instance runs the Claude chat "
                             "(it holds .devtools/chats.json.lock) - use that one",
                             calibration_file=CALIBRATION_FILE if history_lock else None,
                             limits_file=LOG_DIR / "limits.json" if history_lock else None)  # fmt: skip
    threading.Thread(target=_scan_task_costs, name="task-costs", daemon=True).start()
    server = ThreadingHTTPServer((HOST, args.port), make_handler(registry.REPO_ROOT, services, jobs, chats))
    for service in services.values():
        service.start()
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _raise_interrupt)
    print("Devtools: http://localhost:%d  (Ctrl+C stops it and the tools it started)" % args.port, flush=True)
    for service in services.values():
        state = "running" if service.wait_up() else "NOT RUNNING – see %s" % service.log_path
        print("  %-13s http://localhost:%d  %s" % (service.spec["label"], service.spec["port"], state), flush=True)
    status = chats.status()
    print("  %-13s %s" % ("Claude chat", status["claude"] or "unavailable – " + status["hint"]), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        jobs.shutdown()
        chats.shutdown()
        for service in services.values():
            service.stop()


if __name__ == "__main__":
    main()
