#!/usr/bin/env python3
"""Local web server of the backlog viewer (tools/backlog_view.sh). Python 3.8, stdlib only.

Read-only view of docs/tasks/BACKLOG.md and the task files; the page polls /api/version and reloads
the data when a file changes. The one write is POST /api/costs/refresh: re-scan the Claude Code transcripts into
docs/tasks/task_costs.json (tools/task_cost.py) for the Usage column. Binds to 127.0.0.1 only.
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
import backlog_data  # noqa: E402
import static  # noqa: E402
import task_cost  # noqa: E402

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
}
_scan_lock = threading.Lock()


def refresh_costs(tasks_dir: Path, projects_dir: Path) -> int:
    """Re-scan the transcripts into the tasks dir's task_costs.json; the number of tasks with a cost."""
    with _scan_lock:
        return len(task_cost.refresh(projects_dir, tasks_dir / backlog_data.COSTS_FILE))


class Handler(BaseHTTPRequestHandler):
    server_version = "BacklogView/1"
    tasks_dir: Path = backlog_data.TASKS_DIR
    limits_file: Path = backlog_data.LIMITS_FILE
    projects_dir: Path = task_cost.project_dir()

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

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
        path = unquote(urlsplit(self.path).path)
        try:
            if path in STATIC:
                name, ctype = STATIC[path]
                self._send(200, (HERE / name).read_bytes(), ctype)
            elif path == "/api/version":
                self._json({"version": backlog_data.version(self.tasks_dir, self.limits_file)})
            elif path == "/api/backlog":
                data = backlog_data.load(self.tasks_dir, self.limits_file)
                data["version"] = backlog_data.version(self.tasks_dir, self.limits_file)
                self._json(data)
            elif path.startswith("/api/task/"):
                text = backlog_data.read_task(path[len("/api/task/") :], self.tasks_dir)
                if text is None:
                    self._json({"error": "no such task file"}, 404)
                else:
                    self._send(200, text.encode("utf-8"), "text/markdown; charset=utf-8")
            elif path == "/theme.css":
                self._send(200, static.THEME.read_bytes(), "text/css; charset=utf-8")
            elif path.startswith("/fonts/") and static.font(path[len("/fonts/") :]):
                self._send(200, static.font(path[len("/fonts/") :]).read_bytes(), "font/ttf")
            else:
                self._json({"error": "not found"}, 404)
        except (OSError, ValueError, IndexError) as exc:  # e.g. a file read mid-save; the page retries
            self._json({"error": str(exc)}, 500)

    def do_POST(self) -> None:  # noqa: N802 (http.server API)
        path = unquote(urlsplit(self.path).path)
        # a JSON content type can't come from a plain form on another site
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            self._json({"error": "JSON requests only"}, 415)
            return
        if path != "/api/costs/refresh":
            self._json({"error": "not found"}, 404)
            return
        if not Path(self.projects_dir).is_dir():
            self._json({"error": "no Claude Code transcripts in %s" % self.projects_dir}, 404)
            return
        try:
            self._json({"tasks": refresh_costs(self.tasks_dir, Path(self.projects_dir))})
        except OSError as exc:
            self._json({"error": str(exc)}, 500)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    server = ThreadingHTTPServer((HOST, args.port), Handler)
    print("Backlog viewer: http://localhost:%d  (Ctrl+C to stop)" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
