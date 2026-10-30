#!/usr/bin/env python3
"""Devtools hub (tools/devtools.sh): one page for every dev tool. Python 3.8, stdlib only.

Starts the web tools (backlog viewer, unit catalog) as child processes – or reuses ones already running –
and shows them as tabs; runs the command-line tools (check, tests, simulation, screenshots, render, game)
as jobs with live output and the images they wrote. Binds to 127.0.0.1 only.
"""
from __future__ import annotations

import argparse
import json
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import parse_qs, unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
import registry  # noqa: E402
import runner  # noqa: E402
import static  # noqa: E402

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
LOG_DIR = registry.REPO_ROOT / ".devtools"  # service logs, git-ignored
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

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
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
        elif path.startswith("/files/"):
            self._image(path[len("/files/") :])
        elif path == "/theme.css":
            self._send(200, static.THEME.read_bytes(), "text/css; charset=utf-8")
        elif path.startswith("/fonts/") and static.font(path[len("/fonts/") :]):
            self._send(200, static.font(path[len("/fonts/") :]).read_bytes(), "font/ttf")
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802 (http.server API)
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
        parts = path.strip("/").split("/")  # api, <kind>, <id>, [action]
        if parts[:2] == ["api", "jobs"] and len(parts) == 2:
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


def make_handler(repo_root: Path, services: Dict[str, runner.Service], jobs: runner.JobRunner) -> type:
    return type("DevtoolsHandler", (Handler,), {"repo_root": repo_root, "services": services, "jobs": jobs})


def _raise_interrupt(*_: Any) -> None:
    raise KeyboardInterrupt


def main(argv: Optional[List[str]] = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8760)
    args = parser.parse_args(argv)
    services = {spec["id"]: runner.Service(spec, registry.REPO_ROOT, LOG_DIR) for spec in registry.SERVICES}
    jobs = runner.JobRunner(registry.REPO_ROOT)
    server = ThreadingHTTPServer((HOST, args.port), make_handler(registry.REPO_ROOT, services, jobs))
    for service in services.values():
        service.start()
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _raise_interrupt)
    print("Devtools: http://localhost:%d  (Ctrl+C stops it and the tools it started)" % args.port, flush=True)
    for service in services.values():
        state = "running" if service.wait_up() else "NOT RUNNING – see %s" % service.log_path
        print("  %-13s http://localhost:%d  %s" % (service.spec["label"], service.spec["port"], state), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        jobs.shutdown()
        for service in services.values():
            service.stop()


if __name__ == "__main__":
    main()
