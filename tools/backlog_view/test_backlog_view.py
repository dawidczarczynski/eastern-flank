"""Tests for the backlog viewer. Run: python3 -m unittest discover -s tools/backlog_view -p 'test_*.py'"""
import http.client
import json
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import backlog_data  # noqa: E402
import server  # noqa: E402

BACKLOG = """# Backlog

Intro text.

| ID | Title | Status | Depends on |
|---|---|---|---|
| [TASK-001](TASK-001-a.md) | First `task` | 🔵 done | – |
| [TASK-002](TASK-002-b.md) | Second | 🔴 blocked | **TASK-001**, TASK-003 (soft: TASK-004) |
| TASK-003 | Third | 💡 idea | TASK-001 |
| TASK-004 | Fourth | 🔵 done (superseded by X) | – |

Notes after the table.
"""
TASK_002 = """# TASK-002: Second

- **Status**: blocked
- **Layers**: core + ai
- **Model**: sonnet

## Goal

- **Not meta**: below the first section
"""


class BacklogDataTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "BACKLOG.md").write_text(BACKLOG, encoding="utf-8")
        (self.dir / "TASK-002-b.md").write_text(TASK_002, encoding="utf-8")

    def tearDown(self) -> None:
        shutil.rmtree(self.dir)

    def test_rows_keep_priority_order_and_split_dependencies(self) -> None:
        data = backlog_data.load(self.dir)
        rows = {row["id"]: row for row in data["rows"]}
        self.assertEqual([r["id"] for r in data["rows"]], ["TASK-001", "TASK-002", "TASK-003", "TASK-004"])
        self.assertEqual(rows["TASK-002"]["hard"], ["TASK-001", "TASK-003"])
        self.assertEqual(rows["TASK-002"]["soft"], ["TASK-004"])
        self.assertEqual(rows["TASK-001"]["dependents"], ["TASK-002", "TASK-003"])
        self.assertEqual(rows["TASK-001"]["title"], "First `task`")

    def test_status_key_and_extra_text(self) -> None:
        rows = {row["id"]: row for row in backlog_data.load(self.dir)["rows"]}
        self.assertEqual(rows["TASK-004"]["status"], "done")
        self.assertEqual(rows["TASK-004"]["status_text"], "done (superseded by X)")
        self.assertEqual(rows["TASK-002"]["status"], "blocked")

    def test_meta_from_task_file_header_only(self) -> None:
        rows = {row["id"]: row for row in backlog_data.load(self.dir)["rows"]}
        self.assertEqual(rows["TASK-002"]["layers"], "core + ai")
        self.assertEqual(rows["TASK-002"]["model"], "sonnet")
        self.assertNotIn("not meta", backlog_data.task_meta(TASK_002))
        self.assertEqual(backlog_data.model_name("opus (two large models)"), "opus")
        self.assertEqual(backlog_data.model_name("sonnet | opus (hard tasks)"), "sonnet")
        self.assertEqual(backlog_data.model_name("`UnitModels._make_rocket_artillery` – truck"), "")
        # a linked file that does not exist is reported as missing
        self.assertIsNone(rows["TASK-001"]["file"])

    def test_intro_and_notes(self) -> None:
        data = backlog_data.load(self.dir)
        self.assertIn("Intro text.", data["intro"])
        self.assertEqual(data["notes"], "Notes after the table.")

    def test_version_changes_with_files(self) -> None:
        before = backlog_data.version(self.dir)
        path = self.dir / "TASK-002-b.md"
        path.write_text(TASK_002 + "more\n", encoding="utf-8")
        self.assertNotEqual(backlog_data.version(self.dir), before)
        before = backlog_data.version(self.dir)
        (self.dir / "TASK-005-new.md").write_text("# new\n", encoding="utf-8")
        self.assertNotEqual(backlog_data.version(self.dir), before)

    def test_read_task_only_serves_task_files(self) -> None:
        self.assertEqual(backlog_data.read_task("TASK-002-b.md", self.dir), TASK_002)
        self.assertIsNone(backlog_data.read_task("BACKLOG.md", self.dir))
        self.assertIsNone(backlog_data.read_task("../TASK-002-b.md", self.dir))
        self.assertIsNone(backlog_data.read_task("TASK-009-missing.md", self.dir))

    def test_real_backlog_parses(self) -> None:
        data = backlog_data.load()
        self.assertGreater(len(data["rows"]), 0)
        known = set(data["statuses"])
        for row in data["rows"]:
            self.assertIn(row["status"], known, row["id"])


class ServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / "BACKLOG.md").write_text(BACKLOG, encoding="utf-8")
        (self.dir / "TASK-002-b.md").write_text(TASK_002, encoding="utf-8")
        handler = type("TestHandler", (server.Handler,), {"tasks_dir": self.dir})
        self.httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        shutil.rmtree(self.dir)

    def get(self, path: str):
        conn = http.client.HTTPConnection("127.0.0.1", self.httpd.server_address[1], timeout=5)
        conn.request("GET", path)
        res = conn.getresponse()
        body = res.read()
        conn.close()
        return res.status, body

    def test_backlog_and_version(self) -> None:
        status, body = self.get("/api/backlog")
        self.assertEqual(status, 200)
        data = json.loads(body)
        self.assertEqual(len(data["rows"]), 4)
        status, body = self.get("/api/version")
        self.assertEqual(json.loads(body)["version"], data["version"])

    def test_task_file_and_traversal(self) -> None:
        self.assertEqual(self.get("/api/task/TASK-002-b.md"), (200, TASK_002.encode()))
        self.assertEqual(self.get("/api/task/..%2FBACKLOG.md")[0], 404)
        self.assertEqual(self.get("/fonts/..%2F..%2FREADME.md")[0], 404)

    def test_static_files(self) -> None:
        for path in ("/", "/app.js", "/style.css", "/theme.css", "/fonts/JetBrainsMono.ttf"):
            self.assertEqual(self.get(path)[0], 200, path)


if __name__ == "__main__":
    unittest.main()
