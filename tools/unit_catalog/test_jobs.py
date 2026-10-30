"""Tests for the agent job queue (jobs.py) - with a fake `claude` script, never the real CLI.

Run: python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'
"""
import json
import os
import shutil
import stat
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402
import jobs  # noqa: E402
import server  # noqa: E402
import test_catalog as base  # noqa: E402  (module import, so its test classes don't run twice)

# Behaves like `claude -p "/<kind>-unit <id>" --output-format stream-json ...`. The unit id picks the behaviour.
# With --resume the prompt quotes the task in backticks; the run then just reports which session it continued.
FAKE_CLAUDE = r'''#!%(python)s
import json, os, sys, time
prompt = sys.argv[2]
resumed = sys.argv[sys.argv.index("--resume") + 1] if "--resume" in sys.argv else ""
uid = (prompt.split("`")[1] if resumed else prompt).split()[1]
if resumed:
    prompt = "resumed " + resumed
def out(msg):
    print(json.dumps(msg), flush=True)
out({"type": "system", "subtype": "init", "session_id": "sess-1", "model": "fake"})
out({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [
    {"type": "text", "text": "Researching " + uid},
    {"type": "tool_use", "name": "WebSearch", "input": {"query": uid + " dimensions"}}]}})
if uid == "slow_unit" and not resumed:
    time.sleep(30)
if uid == "crash_unit":
    sys.exit(3)
if prompt.startswith("/research-unit"):
    path = os.path.join("docs", "design", "units", "units", uid, "research.json")
    with open(path, "w") as f:
        json.dump({"fields": {"weight_t": {"value": 55, "source": "https://example.org"}}, "summary": "ok"}, f)
out({"type": "result", "subtype": "success", "is_error": uid == "error_unit", "result": "Done: " + prompt,
     "total_cost_usd": 0.12, "session_id": "sess-1"})
'''


class JobsCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="unit_catalog_jobs_")
        self.history = Path(self.tmp) / "state" / "jobs.json"
        self.repo = Path(self.tmp) / "repo"
        self.root = self.repo / "docs" / "design" / "units"
        self.root.mkdir(parents=True)
        catalog.save_classes(self.root, base.CLASSES)
        catalog.create_faction(self.root, base.FACTION)
        for uid in ("k2", "slow_unit", "crash_unit", "error_unit"):
            catalog.create_unit(self.root, uid.upper(), uid)
        self.claude = Path(self.tmp) / "fake_claude"
        self.claude.write_text(FAKE_CLAUDE % {"python": sys.executable})
        self.claude.chmod(self.claude.stat().st_mode | stat.S_IXUSR)
        self.manager = jobs.JobManager(self.repo, self.root, str(self.claude))

    def tearDown(self):
        self.manager.shutdown()
        self.manager.wait_idle(10)
        shutil.rmtree(self.tmp, ignore_errors=True)

    @staticmethod
    def wait_session(manager, job_id):
        """Wait until the running job has printed its init message (session id)."""
        for _ in range(250):
            if manager.get(job_id)["session_id"]:
                return
            threading.Event().wait(0.02)
        raise AssertionError("no session id")


class TestCommands(unittest.TestCase):
    def test_research_command(self):
        cmd = jobs.build_command("/bin/claude", "research", "k2", Path("/repo"))
        self.assertEqual(cmd[:3], ["/bin/claude", "-p", "/research-unit k2"])
        self.assertIn("dontAsk", cmd)
        tools = cmd[-1].split(",")
        self.assertIn("Edit(//repo/docs/design/units/units/k2/research.json)", tools)
        self.assertFalse(any(t.startswith("Bash") for t in tools))
        self.assertEqual([t for t in tools if t.startswith("Edit")], ["Edit(//repo/docs/design/units/units/k2/research.json)"])

    def test_model_command(self):
        cmd = jobs.build_command("claude", "model", "k2", Path("/repo"), "poland")
        self.assertEqual(cmd[2], "/model-unit k2 --faction=poland")
        tools = cmd[-1].split(",")
        self.assertIn("Edit(//repo/src/presentation/models/**)", tools)
        self.assertIn("Edit(//repo/docs/design/units/units/k2/**)", tools)
        self.assertIn("Bash(tools/check.sh:*)", tools)
        self.assertNotIn("Bash", tools)  # never unrestricted shell
        self.assertIn("Edit(//repo/src/presentation/unit_models.gd)", tools)  # connect the model to the game
        self.assertIn("Edit(//repo/tests/unit/test_unit_model*.gd)", tools)
        self.assertNotIn("--resume", cmd)

    def test_resume_command(self):
        cmd = jobs.build_command("claude", "model", "k2", Path("/repo"), "poland", resume="598ecbb6-ca57")
        self.assertIn("`/model-unit k2 --faction=poland`", cmd[2])
        self.assertEqual(cmd[cmd.index("--resume") + 1], "598ecbb6-ca57")
        self.assertEqual(cmd[-1], jobs.build_command("claude", "model", "k2", Path("/repo"), "poland")[-1])
        for bad in ("--fork-session", "a b", "x;rm", "../s"):
            with self.assertRaises(catalog.CatalogError, msg=bad):
                jobs.build_command("claude", "model", "k2", Path("/repo"), resume=bad)

    def test_bad_input_rejected(self):
        for args in [("research", "../x"), ("deploy", "k2"), ("model", "k2", "bad faction"), ("research", "k2", "poland")]:
            with self.assertRaises(catalog.CatalogError, msg=args):
                jobs.build_command("claude", args[0], args[1], Path("/repo"), *args[2:])

    def test_find_claude_env_override(self):
        with mock.patch.dict(os.environ, {jobs.CLAUDE_ENV: "/nonexistent/claude"}):
            self.assertIsNone(jobs.find_claude())
        with mock.patch.dict(os.environ, {jobs.CLAUDE_ENV: sys.executable}):
            self.assertEqual(jobs.find_claude(), sys.executable)


class TestStreamParsing(unittest.TestCase):
    def test_messages(self):
        init = jobs.parse_stream_line(json.dumps({"type": "system", "subtype": "init", "session_id": "s", "model": "m"}))
        self.assertEqual(init[0]["session_id"], "s")
        msg = {"type": "assistant", "parent_tool_use_id": "t1", "message": {"content": [
            {"type": "thinking", "thinking": ""}, {"type": "text", "text": " hi "},
            {"type": "tool_use", "name": "Read", "input": {"file_path": "a.gd"}}]}}  # fmt: skip
        entries = jobs.parse_stream_line(json.dumps(msg))
        self.assertEqual([(e["kind"], e["text"], e["sub"]) for e in entries], [("text", "hi", True), ("tool", "Read: a.gd", True)])
        err = {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": True, "content": "denied"}]}}
        self.assertEqual(jobs.parse_stream_line(json.dumps(err))[0]["kind"], "error")
        res = jobs.parse_stream_line(json.dumps({"type": "result", "result": "ok", "is_error": False, "total_cost_usd": 1.5}))
        self.assertEqual((res[0]["kind"], res[0]["cost_usd"]), ("result", 1.5))

    def test_noise(self):
        self.assertEqual(jobs.parse_stream_line(""), [])
        self.assertEqual(jobs.parse_stream_line(json.dumps({"type": "rate_limit_event"})), [])
        self.assertEqual(jobs.parse_stream_line("plain stderr line")[0]["kind"], "info")


class TestJobManager(JobsCase):
    def test_research_job_applies_result(self):
        job = self.manager.submit("research", "k2")
        self.assertTrue(self.manager.wait_idle(20))
        detail = self.manager.get(job["id"])
        self.assertEqual(detail["state"], "done", detail)
        self.assertEqual(detail["report"]["filled"], ["weight_t"])
        self.assertEqual(detail["session_id"], "sess-1")
        self.assertEqual(detail["cost_usd"], 0.12)
        self.assertIn("WebSearch: k2 dimensions", [e["text"] for e in detail["log"]])
        unit = catalog.load_unit(self.root, "k2")
        self.assertEqual(unit["provenance"]["weight_t"]["verified"], False)

    def test_log_since(self):
        job = self.manager.submit("research", "k2")
        self.manager.wait_idle(20)
        full = self.manager.get(job["id"])
        part = self.manager.get(job["id"], since=2)
        self.assertEqual(part["log"], full["log"][2:])
        self.assertEqual(part["log_from"], 2)

    def test_failures(self):
        a = self.manager.submit("research", "crash_unit")
        b = self.manager.submit("model", "error_unit")
        self.manager.wait_idle(20)
        self.assertEqual(self.manager.get(a["id"])["state"], "failed")
        self.assertIn("code 3", self.manager.get(a["id"])["error"])
        self.assertEqual(self.manager.get(b["id"])["state"], "failed")

    def test_one_job_per_unit_and_queue_order(self):
        slow = self.manager.submit("research", "slow_unit")
        with self.assertRaises(catalog.CatalogError) as ctx:
            self.manager.submit("model", "slow_unit")
        self.assertEqual(ctx.exception.status, 409)
        queued = self.manager.submit("research", "k2")
        self.assertEqual(self.manager.get(queued["id"])["state"], "queued")
        self.assertEqual(self.manager.active_for_unit("k2")["id"], queued["id"])
        self.assertEqual(self.manager.cancel(queued["id"])["state"], "cancelled")
        self.manager.cancel(slow["id"])
        self.assertTrue(self.manager.wait_idle(10))
        self.assertEqual(self.manager.get(slow["id"])["state"], "cancelled")

    def test_submit_validation(self):
        for args, status in [(("research", "nope"), 404), (("research", "../x"), 400), (("x", "k2"), 400),
                             (("model", "k2", "atlantis"), 400)]:  # fmt: skip
            with self.assertRaises(catalog.CatalogError, msg=args) as ctx:
                self.manager.submit(*args)
            self.assertEqual(ctx.exception.status, status, args)

    def test_unavailable_without_claude(self):
        manager = jobs.JobManager(self.repo, self.root, None)
        self.assertFalse(manager.status()["available"])
        with self.assertRaises(catalog.CatalogError) as ctx:
            manager.submit("research", "k2")
        self.assertEqual(ctx.exception.status, 503)


class TestHistoryAndResume(JobsCase):
    def manager_with_history(self):
        return jobs.JobManager(self.repo, self.root, str(self.claude), state_file=self.history)

    def test_history_survives_restart(self):
        first = self.manager_with_history()
        job = first.submit("research", "k2")
        self.assertTrue(first.wait_idle(20))
        second = self.manager_with_history()
        detail = second.get(job["id"])
        self.assertEqual((detail["state"], detail["session_id"], detail["resumable"]), ("done", "sess-1", True))
        self.assertIn("WebSearch: k2 dimensions", [e["text"] for e in detail["log"]])
        self.assertEqual(detail["report"]["filled"], ["weight_t"])
        self.assertNotEqual(second.submit("research", "crash_unit")["id"], job["id"])
        second.wait_idle(20)

    def test_shutdown_interrupts_and_resume_continues_the_session(self):
        first = self.manager_with_history()
        slow = first.submit("model", "slow_unit", "poland")
        self.wait_session(first, slow["id"])
        first.shutdown()
        self.assertTrue(first.wait_idle(10))
        self.assertEqual(first.get(slow["id"])["state"], "interrupted")

        second = self.manager_with_history()
        old = second.get(slow["id"])
        self.assertEqual((old["state"], old["resumable"]), ("interrupted", True))
        self.assertEqual(second.last_for_unit("slow_unit")["id"], slow["id"])
        with mock.patch.object(jobs.claude_cli, "agent_alive", return_value=False):
            new = second.resume(slow["id"])
        self.assertEqual((new["kind"], new["unit_id"], new["faction"], new["resume_of"]), ("model", "slow_unit", "poland", slow["id"]))
        self.assertTrue(second.wait_idle(20))
        detail = second.get(new["id"])
        self.assertEqual(detail["state"], "done", detail)
        self.assertEqual(detail["result"], "Done: resumed sess-1")
        self.assertIsNone(second.last_for_unit("slow_unit"))

    def test_crash_leaves_running_jobs_interrupted(self):
        self.history.parent.mkdir(parents=True)
        base_job = {"kind": "model", "unit_id": "k2", "faction": "", "created": 1.0, "session_id": "sess-9", "log": []}
        self.history.write_text(json.dumps({"counter": 7, "jobs": [
            dict(base_job, id="a-1", state="running"), dict(base_job, id="a-2", state="queued", session_id="")]}))
        manager = self.manager_with_history()
        self.assertEqual(manager.get("a-1")["state"], "interrupted")
        self.assertIn("stopped", manager.get("a-1")["error"])
        self.assertEqual((manager.get("a-2")["state"], manager.get("a-2")["resumable"]), ("cancelled", False))

    def test_unreadable_history_is_ignored(self):
        self.history.parent.mkdir(parents=True)
        self.history.write_text("{not json")
        self.assertEqual(self.manager_with_history().list(), [])

    def test_resume_validation(self):
        job = self.manager.submit("research", "crash_unit")
        self.manager.wait_idle(20)
        self.assertEqual(self.manager.get(job["id"])["state"], "failed")
        with self.assertRaises(catalog.CatalogError) as ctx:
            self.manager.resume("nope")
        self.assertEqual(ctx.exception.status, 404)
        with mock.patch.object(jobs.claude_cli, "agent_alive", return_value=True), self.assertRaises(catalog.CatalogError) as ctx:
            self.manager.resume(job["id"])
        self.assertEqual(ctx.exception.status, 409)
        slow = self.manager.submit("research", "slow_unit")
        with self.assertRaises(catalog.CatalogError) as ctx:
            self.manager.resume(slow["id"])  # still active
        self.assertEqual(ctx.exception.status, 409)
        self.manager.cancel(slow["id"])
        self.manager.wait_idle(10)
        self.manager._jobs[job["id"]].session_id = ""
        with self.assertRaises(catalog.CatalogError) as ctx:
            self.manager.resume(job["id"])
        self.assertEqual(ctx.exception.status, 400)


class TestJobsServer(JobsCase):
    def setUp(self):
        super().setUp()
        self.httpd = server.make_server(0, self.root, Path(self.tmp) / "shots", job_manager=self.manager)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(5)
        super().tearDown()

    req = base.ServerCase.req
    jreq = base.ServerCase.jreq

    def test_job_endpoints(self):
        self.assertTrue(self.jreq("GET", "/api/ai")[1]["available"])
        status, job = self.jreq("POST", "/api/jobs", {"kind": "research", "unit_id": "k2"})
        self.assertEqual(status, 201)
        self.manager.wait_idle(20)
        status, data = self.jreq("GET", "/api/jobs/%s?since=1" % job["id"])
        self.assertEqual((status, data["state"], data["log_from"]), (200, "done", 1))
        self.assertEqual(self.jreq("GET", "/api/jobs")[1]["jobs"][0]["id"], job["id"])
        self.assertIsNone(self.jreq("GET", "/api/units/k2")[1]["job"])
        self.assertEqual(self.jreq("GET", "/api/jobs/nope")[0], 404)
        self.assertEqual(self.jreq("POST", "/api/jobs", {"kind": "rm -rf", "unit_id": "k2"})[0], 400)

    def test_running_job_shown_on_unit_and_cancel(self):
        _, job = self.jreq("POST", "/api/jobs", {"kind": "research", "unit_id": "slow_unit"})
        self.assertEqual(self.jreq("GET", "/api/units/slow_unit")[1]["job"]["id"], job["id"])
        self.wait_session(self.manager, job["id"])
        self.assertEqual(self.jreq("POST", "/api/jobs/%s/cancel" % job["id"], {})[0], 200)
        self.assertTrue(self.manager.wait_idle(10))
        self.assertEqual(self.jreq("GET", "/api/units/slow_unit")[1]["last_job"]["id"], job["id"])
        status, resumed = self.jreq("POST", "/api/jobs/%s/resume" % job["id"], {})
        self.assertEqual((status, resumed["resume_of"]), (201, job["id"]))
        self.manager.cancel(resumed["id"])
        self.assertTrue(self.manager.wait_idle(10))

    def test_job_post_needs_csrf_headers(self):
        import http.client

        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("POST", "/api/jobs", body=b'{"kind":"research","unit_id":"k2"}',
                     headers={"Content-Type": "text/plain"})  # fmt: skip
        self.assertEqual(conn.getresponse().status, 403)
        conn.close()
        self.assertEqual(self.manager.list(), [])


if __name__ == "__main__":
    unittest.main()
