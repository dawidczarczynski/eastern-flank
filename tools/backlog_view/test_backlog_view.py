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

    def test_topics_from_notes_sections(self) -> None:
        notes = "Preamble TASK-001.\n\nTerrain (TASK-010 … TASK-020, look): text\n\n030 → 031\n\nHUD v3 (vision, TASK-040 … TASK-045): more\n"
        sections = backlog_data.topic_sections(notes)
        self.assertEqual([(s["name"], s["first"], s["last"]) for s in sections], [("Terrain", "TASK-010", "TASK-020"), ("HUD v3", "TASK-040", "TASK-045")])
        rows = [{"id": i} for i in ["TASK-001", "TASK-012a", "TASK-031", "TASK-035", "TASK-041", "TASK-050", "TASK-060"]]
        topics = backlog_data.assign_topics(rows, sections, {"TASK-060": "Custom"})
        self.assertEqual(topics, {
            "TASK-001": "Foundation",  # before the first range
            "TASK-012a": "Terrain",  # inside a range
            "TASK-031": "Terrain",  # named in the section's text
            "TASK-035": "Terrain",  # the last section starting before it
            "TASK-041": "HUD v3",
            "TASK-050": "HUD v3",
            "TASK-060": "Custom",  # `- **Topic**:` in the task file
        })
        self.assertEqual(backlog_data.id_key("TASK-039a"), 3901)

    def test_tree_hangs_tasks_under_their_deepest_dependency(self) -> None:
        def row(order, task_id, hard=(), soft=()):
            return {"order": order, "id": task_id, "hard": list(hard), "soft": list(soft)}

        rows = [
            row(0, "TASK-001"),
            row(1, "TASK-002", ["TASK-001"]),
            row(2, "TASK-003", ["TASK-001", "TASK-002"]),
            row(3, "TASK-004", soft=["TASK-002"]),  # only soft links: hangs under them
            row(4, "TASK-005", ["TASK-003", "TASK-010"]),
            row(5, "TASK-010"),
            row(6, "TASK-011", ["TASK-012"]),  # a cycle is cut, not looped
            row(7, "TASK-012", ["TASK-011"]),
        ]
        topic_of = {r["id"]: ("B" if r["id"] == "TASK-010" else "A") for r in rows}
        tree = backlog_data.build_tree(rows, topic_of, ["A", "B", "Empty"])
        self.assertEqual([t["name"] for t in tree], ["A", "B"])

        def shape(node):
            return [node["id"], [shape(c) for c in node["children"]]]

        a = tree[0]["roots"]
        self.assertEqual([shape(n) for n in a], [
            ["TASK-001", [["TASK-002", [["TASK-003", [["TASK-005", []]]], ["TASK-004", []]]]]],
            ["TASK-011", [["TASK-012", []]]],
        ])
        task_003 = a[0]["children"][0]["children"][0]
        self.assertEqual(task_003["also"], ["TASK-001"])
        self.assertEqual(task_003["children"][0]["external"], [{"id": "TASK-010", "topic": "B"}])
        self.assertEqual([n["id"] for n in tree[1]["roots"]], ["TASK-010"])

    def test_real_backlog_tree_holds_every_task_once(self) -> None:
        data = backlog_data.load()

        def ids(node):
            return [node["id"]] + [i for c in node["children"] for i in ids(c)]

        listed = [i for topic in data["tree"] for root in topic["roots"] for i in ids(root)]
        self.assertEqual(sorted(listed), sorted(r["id"] for r in data["rows"]))
        self.assertTrue(all(r["topic"] for r in data["rows"]))

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
        handler = type("TestHandler", (server.Handler,), {"tasks_dir": self.dir, "limits_file": self.dir / "limits.json",
                                                          "projects_dir": self.dir / "no-projects"})  # fmt: skip
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

    def test_usage_column_data_and_cost_refresh(self) -> None:
        data = json.loads(self.get("/api/backlog")[1])
        self.assertEqual(data["usage"]["calibration"]["five_hour"], {"percent_per_cost": None, "sessions": 0})
        self.assertIsNone(data["usage"]["costs_scanned"])
        self.assertTrue(all(r["usage"] is None for r in data["rows"]), "no costs yet")
        projects = self.dir / "projects"
        projects.mkdir()
        lines = [{"type": "user", "timestamp": "2026-10-01T10:00:00Z", "message": {"content": "<command-name>/implement-task</command-name>\n<command-args>1</command-args>"}},
                 {"type": "assistant", "timestamp": "2026-10-01T10:01:00Z", "message": {"id": "a", "model": "claude-sonnet-5-5", "usage": {"output_tokens": 100000}}}]
        (projects / "s.jsonl").write_text("\n".join(json.dumps(x) for x in lines), encoding="utf-8")
        self.httpd.RequestHandlerClass.projects_dir = projects
        before = self.get("/api/version")[1]
        self.assertEqual(self.post("/api/costs/refresh", "text/plain")[0], 415)
        self.assertEqual(self.post("/api/costs/refresh"), (200, {"tasks": 1}))
        self.assertNotEqual(self.get("/api/version")[1], before, "the costs file is followed")
        rows = {r["id"]: r for r in json.loads(self.get("/api/backlog")[1])["rows"]}
        self.assertEqual((rows["TASK-001"]["usage"]["kind"], rows["TASK-001"]["usage"]["cost"]), ("actual", 1.5))
        self.assertEqual(rows["TASK-002"]["usage"]["kind"], "forecast")
        self.assertTrue(rows["TASK-002"]["usage"]["low_confidence"])

    def post(self, path: str, ctype: str = "application/json"):
        conn = http.client.HTTPConnection("127.0.0.1", self.httpd.server_address[1], timeout=10)
        conn.request("POST", path, body="{}", headers={"Content-Type": ctype})
        res = conn.getresponse()
        body = json.loads(res.read())
        conn.close()
        return res.status, body

    def test_static_files(self) -> None:
        for path in ("/", "/app.js", "/style.css", "/theme.css", "/fonts/JetBrainsMono.ttf"):
            self.assertEqual(self.get(path)[0], 200, path)


if __name__ == "__main__":
    unittest.main()
