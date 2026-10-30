#!/usr/bin/env python3
"""Local web server of the unit catalog tool (TASK-037). Python 3.8, stdlib only.

Binds to 127.0.0.1 only - there is deliberately no option to change that.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import re
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Optional, Tuple
from urllib.parse import parse_qs, unquote, urlsplit
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "web_ui"))
import catalog  # noqa: E402
import jobs  # noqa: E402
import static  # noqa: E402  (shared look of the dev web tools: /theme.css, /fonts/)

HOST = "127.0.0.1"
HERE = Path(__file__).resolve().parent
FONTS_DIR = catalog.REPO_ROOT / "assets" / "fonts" / "ibm_plex"
JOB_HISTORY = catalog.REPO_ROOT / ".unit_catalog" / "jobs.json"  # local, git-ignored
STATIC = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}
SERVED_EXTENSIONS = {".json", ".md", ".png", ".jpg", ".jpeg", ".webp", ".ttf"}
MAX_BODY = 25 * 1024 * 1024
mimetypes.add_type("font/ttf", ".ttf")
mimetypes.add_type("application/javascript", ".js")
USER_AGENT = "EasternFlankUnitCatalog/1 (local reference tool)"  # Wikimedia rejects requests without one


def fetch_image(url: str) -> bytes:
    """Download an image candidate (https only, at most MAX_IMAGE_BYTES)."""
    if not url.startswith("https://"):
        raise catalog.CatalogError([{"field": "url", "message": "only https:// URLs"}])
    try:
        with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=30) as resp:
            data = resp.read(catalog.MAX_IMAGE_BYTES + 1)
    except (OSError, ValueError) as exc:
        raise catalog.CatalogError([{"field": "url", "message": "download failed: %s" % exc}], 502)
    if len(data) > catalog.MAX_IMAGE_BYTES:
        raise catalog.CatalogError([{"field": "url", "message": "image larger than 15 MB"}], 413)
    return data  # type: ignore[no-any-return]


# A Wikimedia original can be 10+ MB; its 1920 px thumbnail (a standard size) is plenty for a modelling reference.
WIKIMEDIA_RE = re.compile(r"(https://upload\.wikimedia\.org/wikipedia/[^/]+)/([0-9a-f]/[0-9a-f]{2})/([^/?#]+\.(?:jpe?g|png|webp))", re.I)
REFERENCE_WIDTH = 1920


def reference_urls(url: str) -> list:
    """URLs to try for a reference image, best first: a reduced Wikimedia thumbnail, then the original."""
    m = WIKIMEDIA_RE.fullmatch(url)
    if m is None:
        return [url]
    return ["%s/thumb/%s/%s/%dpx-%s" % (m.group(1), m.group(2), m.group(3), REFERENCE_WIDTH, m.group(3)), url]


class Handler(BaseHTTPRequestHandler):
    server_version = "UnitCatalog/1"
    root: Path = catalog.DEFAULT_ROOT
    screenshots: Path = catalog.DEFAULT_SCREENSHOTS
    fonts: Path = FONTS_DIR
    fetch: Callable[[str], bytes] = staticmethod(fetch_image)  # type: ignore[assignment]
    jobs: Any = None  # jobs.JobManager

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
        split = urlsplit(self.path)
        raw_path, self.query = split.path, parse_qs(split.query)
        path = unquote(raw_path)
        try:
            if path.startswith("/api/"):
                self._api(method, [unquote(p) for p in raw_path[len("/api/"):].strip("/").split("/")])
            elif path.startswith("/files/") and method in ("GET", "HEAD"):
                self._file(path[len("/files/"):])
            elif method in ("GET", "HEAD") and path == "/theme.css":
                self._send(200, static.THEME.read_bytes(), "text/css; charset=utf-8")
            elif method in ("GET", "HEAD") and path.startswith("/fonts/") and static.font(path[len("/fonts/"):]):
                self._send(200, static.font(path[len("/fonts/"):]).read_bytes(), "font/ttf")
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
            self._json(200, self._unit(parts[1]))
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
        elif len(parts) == 4 and parts[0] == "units" and parts[2:] == ["images", "restore"] and method == "POST":
            self._json(200, {"report": self._restore(parts[1]), **self._unit(parts[1])})
        elif parts == ["images", "restore"] and method == "POST":
            reports = [self._restore(uid) for uid in catalog.list_unit_ids(r)]
            self._json(200, {"reports": [x for x in reports if x["restored"] or x["failed"]]})
        elif len(parts) == 4 and parts[0] == "units" and parts[2] == "images" and method == "DELETE":
            catalog.delete_image(r, parts[1], parts[3])
            self._json(200, catalog.unit_detail(r, parts[1], self.screenshots))
        elif len(parts) == 4 and parts[0] == "units" and parts[2:] == ["research", "apply"] and method == "POST":
            report = catalog.apply_research(r, parts[1])
            self._json(200, {"report": report, **self._unit(parts[1])})
        elif len(parts) == 3 and parts[0] == "units" and parts[2] == "candidates" and method == "POST":
            self._candidate(parts[1], self._body())
        elif parts == ["ai"] and method == "GET":
            self._json(200, self.jobs.status())
        elif parts == ["jobs"] and method == "GET":
            self._json(200, {"jobs": self.jobs.list()})
        elif parts == ["jobs"] and method == "POST":
            b = self._body()
            self._json(201, self.jobs.submit(b.get("kind"), b.get("unit_id"), b.get("faction", "")))
        elif len(parts) == 2 and parts[0] == "jobs" and method == "GET":
            since = self.query.get("since", ["0"])[0]
            self._json(200, self.jobs.get(parts[1], int(since) if since.isdigit() else 0))
        elif len(parts) == 3 and parts[0] == "jobs" and parts[2] == "cancel" and method == "POST":
            self._json(200, self.jobs.cancel(parts[1]))
        elif len(parts) == 3 and parts[0] == "jobs" and parts[2] == "resume" and method == "POST":
            self._json(201, self.jobs.resume(parts[1]))
        elif parts == ["factions"] and method == "POST":
            self._json(201, catalog.create_faction(r, self._body()))
        elif len(parts) == 2 and parts[0] == "factions" and method == "PUT":
            self._json(200, catalog.save_faction(r, parts[1], self._body()))
        else:
            self._error(404, "unknown API route")

    def _unit(self, unit_id: str) -> Any:
        detail = catalog.unit_detail(self.root, unit_id, self.screenshots)
        detail["job"] = self.jobs.active_for_unit(unit_id)
        detail["last_job"] = None if detail["job"] else self.jobs.last_for_unit(unit_id)
        return detail

    def _fetch_reference(self, url: str) -> bytes:
        error: Optional[catalog.CatalogError] = None
        for candidate in reference_urls(url):
            try:
                data = self.fetch(candidate)
            except catalog.CatalogError as exc:
                error = exc
                continue
            if catalog.sniff_image(data) is not None:
                return data
            error = catalog.CatalogError([{"field": "url", "message": "%s is not an image" % candidate}])
        raise error  # type: ignore[misc]

    def _restore(self, unit_id: str) -> Any:
        """Re-download the unit's images that are listed in unit.json but missing on disk."""
        unit = catalog.load_unit(self.root, unit_id)
        by_file = {i["file"]: i for i in unit.get("images", [])}
        restored, failed = [], []
        for file in catalog.missing_image_files(self.root, unit):
            url = by_file[file].get("source_url", "")
            if not url.startswith("https://"):
                failed.append({"file": file, "message": "no https source URL - only the original computer had this file"})
                continue
            try:
                catalog.restore_image(self.root, unit_id, file, self._fetch_reference(url))
                restored.append(file)
            except catalog.CatalogError as exc:
                failed.append({"file": file, "message": "; ".join(e["message"] for e in exc.errors)})
        return {"unit_id": unit_id, "restored": restored, "failed": failed}

    def _candidate(self, unit_id: str, body: Any) -> None:
        """Download (`action: download`) or drop (`action: dismiss`) an AI-proposed image."""
        url, action = body.get("url"), body.get("action")
        cand = catalog.find_candidate(self.root, unit_id, url)
        if action == "dismiss":
            catalog.dismiss_candidate(self.root, unit_id, url)
            self._json(200, self._unit(unit_id))
        elif action == "download":
            data = self._fetch_reference(cand["url"])
            note = " ".join(x for x in (cand.get("note", ""), cand.get("source_page", "")) if x)
            entry = catalog.add_image_bytes(self.root, unit_id, cand["view"], data, cand["url"],
                                            cand.get("license", ""), note, drop_candidate=cand["url"])  # fmt: skip
            self._json(201, {"image": entry, **self._unit(unit_id)})
        else:
            raise catalog.CatalogError([{"field": "action", "message": "must be download or dismiss"}])

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
                fonts: Optional[Path] = None, fetch: Optional[Callable[[str], bytes]] = None,
                job_manager: Optional[jobs.JobManager] = None) -> ThreadingHTTPServer:  # fmt: skip
    """Create (but don't start) the server. Always bound to 127.0.0.1; port 0 picks a free port."""
    data_root = Path(root) if root else catalog.DEFAULT_ROOT
    manager = job_manager or jobs.JobManager(catalog.REPO_ROOT, data_root, jobs.find_claude(),
                                             state_file=None if root else JOB_HISTORY)  # fmt: skip
    handler = type("BoundHandler", (Handler,), {
        "root": data_root,
        "screenshots": Path(screenshots) if screenshots else catalog.DEFAULT_SCREENSHOTS,
        "fonts": Path(fonts) if fonts else FONTS_DIR,
        "fetch": staticmethod(fetch or fetch_image),
        "jobs": manager,
    })  # fmt: skip
    httpd = ThreadingHTTPServer((HOST, port), handler)
    httpd.jobs = manager  # type: ignore[attr-defined]
    return httpd


def _raise_interrupt(signum: int, frame: Any) -> None:
    raise KeyboardInterrupt


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
    ai = httpd.jobs.status()  # type: ignore[attr-defined]
    print("AI jobs: " + (ai["claude"] if ai["available"] else "unavailable - " + ai["hint"]), flush=True)
    # closing the terminal or `kill` shut down like Ctrl+C, so running jobs are saved as interrupted
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _raise_interrupt)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.jobs.shutdown()  # type: ignore[attr-defined]
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
