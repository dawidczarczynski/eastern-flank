#!/usr/bin/env python3
"""Local web server of the backlog viewer (tools/backlog_view.sh). Python 3.8, stdlib only.

Read-only view of docs/tasks/BACKLOG.md and the task files; the page polls /api/version and reloads
the data when a file changes. Binds to 127.0.0.1 only.
"""
from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import backlog_data  # noqa: E402

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
FONTS_DIR = HERE.parent.parent / "assets" / "fonts" / "ibm_plex"
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "BacklogView/1"
    tasks_dir: Path = backlog_data.TASKS_DIR

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
                self._json({"version": backlog_data.version(self.tasks_dir)})
            elif path == "/api/backlog":
                data = backlog_data.load(self.tasks_dir)
                data["version"] = backlog_data.version(self.tasks_dir)
                self._json(data)
            elif path.startswith("/api/task/"):
                text = backlog_data.read_task(path[len("/api/task/") :], self.tasks_dir)
                if text is None:
                    self._json({"error": "no such task file"}, 404)
                else:
                    self._send(200, text.encode("utf-8"), "text/markdown; charset=utf-8")
            elif path.startswith("/fonts/") and path.endswith(".ttf") and "/" not in path[len("/fonts/") :]:
                font = FONTS_DIR / path[len("/fonts/") :]
                if font.is_file():
                    self._send(200, font.read_bytes(), "font/ttf")
                else:
                    self._json({"error": "not found"}, 404)
            else:
                self._json({"error": "not found"}, 404)
        except (OSError, ValueError, IndexError) as exc:  # e.g. a file read mid-save; the page retries
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
