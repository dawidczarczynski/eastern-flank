#!/usr/bin/env python3
"""Local web server of the unit catalog tool (TASK-037). Python 3.8, stdlib only.

Binds to 127.0.0.1 only - there is deliberately no option to change that.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional, Tuple
from urllib.parse import unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
FONTS_DIR = catalog.REPO_ROOT / "assets" / "fonts" / "ibm_plex"
STATIC = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}
SERVED_EXTENSIONS = {".json", ".md", ".png", ".jpg", ".jpeg", ".webp", ".ttf"}
MAX_BODY = 25 * 1024 * 1024
mimetypes.add_type("font/ttf", ".ttf")
mimetypes.add_type("application/javascript", ".js")


class Handler(BaseHTTPRequestHandler):
    server_version = "UnitCatalog/1"
    root: Path = catalog.DEFAULT_ROOT
    screenshots: Path = catalog.DEFAULT_SCREENSHOTS
    fonts: Path = FONTS_DIR

    def log_message(self, fmt: str, *args: Any) -> None:  # keep the console quiet
        if "-q" not in sys.argv and getattr(self.server, "verbose", False):
            super().log_message(fmt, *args)

    # ---- helpers
    def _send(self, status: int, body: bytes, ctype: str, cache: str = "no-store") -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, status: int, data: Any) -> None:
        self._send(status, catalog.dumps(data).encode("utf-8"), "application/json; charset=utf-8")

    def _error(self, status: int, message: str) -> None:
        self._json(status, {"errors": [{"field": "request", "message": message}]})

    def _body(self) -> Any:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise catalog.CatalogError([{"field": "request", "message": "bad Content-Length"}])
        if length < 0:
            raise catalog.CatalogError([{"field": "request", "message": "bad Content-Length"}])
        if length > MAX_BODY:
            raise catalog.CatalogError([{"field": "request", "message": "body too large"}], 413)
        raw = self.rfile.read(length) if length else b""
        try:
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except (ValueError, UnicodeDecodeError, RecursionError):
            raise catalog.CatalogError([{"field": "request", "message": "invalid JSON"}])
        if not isinstance(data, dict):
            raise catalog.CatalogError([{"field": "request", "message": "body must be a JSON object"}])
        return data

    def _csrf_ok(self) -> bool:
        """Mutating requests need a JSON content type and, if sent, a localhost Origin."""
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/json":
            return False
        origin = self.headers.get("Origin")
        if origin is not None:
            port = self.server.server_address[1]
            return origin in ("http://localhost:%d" % port, "http://127.0.0.1:%d" % port)
        return True

    def _host_ok(self) -> bool:
        """Reject foreign Host headers (DNS rebinding protection)."""
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
        return host in ("localhost", "127.0.0.1", "")

    # ---- dispatch
    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_PUT(self) -> None:
        self._dispatch("PUT")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_DELETE(self) -> None:
        self._dispatch("DELETE")

    def _dispatch(self, method: str) -> None:
        if not self._host_ok():
            self._error(403, "forbidden host")
            return
        if method != "GET" and not self._csrf_ok():
            self._error(403, "mutating requests need Content-Type: application/json and a localhost Origin")
            return
        raw_path = urlsplit(self.path).path
        path = unquote(raw_path)
        try:
            if path.startswith("/api/"):
                self._api(method, [unquote(p) for p in raw_path[len("/api/"):].strip("/").split("/")])
            elif path.startswith("/files/") and method in ("GET", "HEAD"):
                self._file(path[len("/files/"):])
            elif method in ("GET", "HEAD") and path in STATIC:
                body = (HERE / STATIC[path]).read_bytes()
                ctype = mimetypes.guess_type(STATIC[path])[0] or "text/plain"
                self._send(200, body, ctype + "; charset=utf-8")
            else:
                self._error(404, "not found")
        except catalog.CatalogError as exc:
            self._json(exc.status, {"errors": exc.errors})
        except Exception as exc:  # pragma: no cover - last resort, keep the server alive
            self._error(500, "internal error")

    def _api(self, method: str, parts: Any) -> None:
        r = self.root
        if parts == ["catalog"] and method == "GET":
            self._json(200, catalog.catalog_summary(r))
        elif parts == ["classes"] and method == "PUT":
            self._json(200, catalog.save_classes(r, self._body().get("classes")))
        elif parts == ["units"] and method == "POST":
            body = self._body()
            created = catalog.create_unit(
                r, body.get("real_name", ""), body.get("id") or None,
                **{k: body[k] for k in ("class", "mobility", "operators") if k in body},
            )  # fmt: skip
            self._json(201, catalog.unit_detail(r, created["id"], self.screenshots))
        elif len(parts) == 2 and parts[0] == "units" and method == "GET":
            self._json(200, catalog.unit_detail(r, parts[1], self.screenshots))
        elif len(parts) == 2 and parts[0] == "units" and method == "PUT":
            catalog.update_unit(r, parts[1], self._body())
            self._json(200, catalog.unit_detail(r, parts[1], self.screenshots))
        elif len(parts) == 3 and parts[0] == "units" and parts[2] == "images" and method == "POST":
            b = self._body()
            entry = catalog.add_image(
                r, parts[1], b.get("view", ""), b.get("data", ""),
                b.get("source_url", ""), b.get("license", ""), b.get("note", ""),
            )  # fmt: skip
            self._json(201, {"image": entry, **catalog.unit_detail(r, parts[1], self.screenshots)})
        elif len(parts) == 4 and parts[0] == "units" and parts[2] == "images" and method == "DELETE":
            catalog.delete_image(r, parts[1], parts[3])
            self._json(200, catalog.unit_detail(r, parts[1], self.screenshots))
        elif parts == ["factions"] and method == "POST":
            self._json(201, catalog.create_faction(r, self._body()))
        elif len(parts) == 2 and parts[0] == "factions" and method == "PUT":
            self._json(200, catalog.save_faction(r, parts[1], self._body()))
        else:
            self._error(404, "unknown API route")

    def _file(self, rel: str) -> None:
        base, sub = self.root, rel
        if rel.startswith("fonts/"):
            base, sub = self.fonts, rel[len("fonts/"):]
        elif rel.startswith("screenshots/"):
            base, sub = self.screenshots, rel[len("screenshots/"):]
        target = catalog.resolve_inside(base, sub)
        if target is None or target.suffix.lower() not in SERVED_EXTENSIONS:
            self._error(403, "forbidden")
            return
        if not target.is_file():
            self._error(404, "not found")
            return
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        if target.suffix.lower() in (".json", ".md"):
            ctype += "; charset=utf-8"
        self._send(200, target.read_bytes(), ctype)


def make_server(port: int, root: Optional[Path] = None, screenshots: Optional[Path] = None,
                fonts: Optional[Path] = None) -> ThreadingHTTPServer:  # fmt: skip
    """Create (but don't start) the server. Always bound to 127.0.0.1; port 0 picks a free port."""
    handler = type("BoundHandler", (Handler,), {
        "root": Path(root) if root else catalog.DEFAULT_ROOT,
        "screenshots": Path(screenshots) if screenshots else catalog.DEFAULT_SCREENSHOTS,
        "fonts": Path(fonts) if fonts else FONTS_DIR,
    })  # fmt: skip
    return ThreadingHTTPServer((HOST, port), handler)


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Unit catalog tool (localhost only)")
    parser.add_argument("--port", type=int, default=8765, help="1-65535")
    parser.add_argument("--root", default=None, help="data root (default: docs/design/units)")
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        print("Invalid port %d: must be between 1 and 65535" % args.port, file=sys.stderr)
        return 2
    try:
        httpd = make_server(args.port, Path(args.root) if args.root else None)
    except OSError as exc:
        print("Cannot listen on %s:%d: %s" % (HOST, args.port, exc), file=sys.stderr)
        return 1
    httpd.verbose = True  # type: ignore[attr-defined]
    print("Unit catalog: http://localhost:%d" % httpd.server_address[1], flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
