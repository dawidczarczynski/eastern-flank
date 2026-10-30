"""Tests for the devtools Claude chat. Run: python3 -m unittest discover -s tools/devtools -p 'test_*.py'"""
import http.client
import json
import os
import shutil
import stat
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chat  # noqa: E402
import runner  # noqa: E402
import server  # noqa: E402

# Stands in for `claude -p --input-format stream-json`: logs its argv, answers every stdin message with an echo.
FAKE_CLAUDE = r'''#!%s
import json, sys, time
args = sys.argv[1:]
with open(%r, "a") as f:
    f.write(json.dumps(args) + "\n")
sid = args[args.index("--resume") + 1] if "--resume" in args else "sess-1"
cost = 0.0
for line in sys.stdin:
    text = json.loads(line)["message"]["content"]
    print(json.dumps({"type": "system", "subtype": "init", "session_id": sid, "model": "fake"}), flush=True)
    if text == "hang":
        time.sleep(60)
    if text == "crash":
        sys.exit(3)
    cost += 0.5
    print(json.dumps({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "unifiedWindows": {
        "five_hour": {"utilization": 0.25 + cost / 10, "resetsAt": 1700000000}, "seven_day": {"utilization": 0.1, "resetsAt": 1700500000}}}}), flush=True)
    usage = {"input_tokens": 2, "cache_read_input_tokens": int(cost * 1000), "cache_creation_input_tokens": 100, "output_tokens": 8}
    print(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "echo: " + text}], "usage": usage}}), flush=True)
    print(json.dumps({"type": "assistant", "parent_tool_use_id": "t1", "message": {"content": [], "usage": {"input_tokens": 99999}}}), flush=True)
    print(json.dumps({"type": "result", "result": "x", "is_error": False, "total_cost_usd": cost, "session_id": sid,
                      "modelUsage": {"m": {"contextWindow": 200000}, "sub": {"contextWindow": 1000000}}}), flush=True)
'''

BACKLOG = """# Backlog

| ID | Title | Status | Depends on |
|---|---|---|---|
| [TASK-001](TASK-001-a.md) | First `thing` | 🔵 done | – |
| [TASK-002](TASK-002-b.md) | Second thing | 🟢 ready | TASK-001 |
| TASK-003 | Just an idea | 💡 idea | – |
"""


class ChatTestBase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        (self.root / "docs" / "tasks").mkdir(parents=True)
        (self.root / "docs" / "tasks" / "BACKLOG.md").write_text(BACKLOG, encoding="utf-8")
        self.argv_log = self.root / "argv.log"
        self.claude = self.root / "fake-claude"
        self.claude.write_text(FAKE_CLAUDE % (sys.executable, str(self.argv_log)), encoding="utf-8")
        self.claude.chmod(self.claude.stat().st_mode | stat.S_IEXEC)
        self.probe_message = None
        self.managers = []

    def tearDown(self) -> None:
        for manager in self.managers:
            manager.shutdown()
        shutil.rmtree(self.root, ignore_errors=True)

    def manager(self, **kw) -> chat.ChatManager:
        kw.setdefault("busy_probe", lambda: self.probe_message)
        kw.setdefault("changed", lambda: [" M src/x.gd"])
        m = chat.ChatManager(self.root, str(self.claude), **kw)
        self.managers.append(m)
        return m

    def launches(self) -> list:
        if not self.argv_log.exists():
            return []
        return [json.loads(line) for line in self.argv_log.read_text().splitlines()]

    def kinds(self, detail: dict) -> list:
        return [(e["kind"], e.get("text", "")) for e in detail["log"] if e["kind"] != "info"]


class PermissionsTest(unittest.TestCase):
    def test_allow_list_is_scoped_to_the_repo_and_the_project_tools(self) -> None:
        perms = chat.permissions(Path("/repo"))
        self.assertIn("Edit(//repo/**)", perms["allow"])
        self.assertIn("Bash(tools/check.sh:*)", perms["allow"])
        self.assertIn("Bash(git diff:*)", perms["allow"])
        self.assertNotIn("Bash", perms["allow"])
        self.assertFalse([t for t in perms["allow"] if t.startswith("Bash(git commit") or t.startswith("Bash(git push")])
        self.assertIn("Edit(//repo/.git/**)", perms["deny"])
        self.assertIn("Edit(//repo/.godot/**)", perms["deny"])
        for git in ("commit", "push", "reset", "stash"):
            self.assertIn("Bash(git %s:*)" % git, perms["deny"])

    def test_command_never_runs_unrestricted_and_validates_the_session(self) -> None:
        cmd = chat.build_command("claude", Path("/repo"))
        self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "auto")
        self.assertEqual(cmd[cmd.index("--permission-prompts") + 1], "none")
        self.assertIn("stream-json", cmd[cmd.index("--input-format") + 1])
        self.assertNotIn("--resume", cmd)
        self.assertEqual(chat.build_command("claude", Path("/repo"), "abc-1")[-2:], ["--resume", "abc-1"])
        with self.assertRaises(chat.ChatError):
            chat.build_command("claude", Path("/repo"), "--dangerously-skip-permissions")


def parse_error(text: str) -> str:
    msg = {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": True, "content": text}]}}
    return chat.claude_cli.parse_stream_line(json.dumps(msg))[0]["text"]


class StreamParseTest(unittest.TestCase):
    def test_permission_refusals_are_shortened(self) -> None:
        msg = {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": True, "content":
               "Permission to use Bash has been denied because Claude Code is running in don't ask mode. IMPORTANT: ..."}]}}
        entries = chat.claude_cli.parse_stream_line(json.dumps(msg))
        self.assertEqual(entries, [{"kind": "error", "text": "denied: Bash (not on the allow-list)", "sub": False}])
        rule = "Permission to use Bash with command git commit -m x has been denied."
        self.assertEqual(parse_error(rule), "denied: Bash git commit -m x (deny rule)")
        classifier = ("Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Data Exfiltration]. "
                      "If you have other tasks ...")
        self.assertEqual(parse_error(classifier), "blocked by the auto mode classifier: Data Exfiltration")


class ChatManagerTest(ChatTestBase):
    def test_free_chat_keeps_one_process_across_messages(self) -> None:
        m = self.manager()
        s = m.create(text="hello")
        self.assertTrue(m.wait_idle(s["id"]))
        d = m.get(s["id"])
        self.assertEqual(d["state"], "idle")
        self.assertEqual(d["session_id"], "sess-1")
        self.assertEqual(d["cost_usd"], 0.5)
        self.assertEqual(d["changed_files"], [" M src/x.gd"])
        self.assertEqual(self.kinds(d), [("user", "hello"), ("text", "echo: hello"), ("turn", "")])
        m.send(s["id"], "again")
        self.assertTrue(m.wait_idle(s["id"]))
        d = m.get(s["id"], since=d["log_from"] + len(d["log"]))
        self.assertEqual(self.kinds(d), [("user", "again"), ("text", "echo: again"), ("turn", "")])
        self.assertEqual(d["cost_usd"], 1.0)
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(sum(1 for e in m.get(s["id"])["log"] if e["kind"] == "info"), 1, "init shown once per process")

    def test_usage_limits_and_context_are_tracked_not_logged(self) -> None:
        state = self.root / ".devtools" / "chats.json"
        m = self.manager(state_file=state)
        self.assertIsNone(m.status()["limits"])
        s = m.create(text="hello")
        self.assertTrue(m.wait_idle(s["id"]))
        limits = m.status()["limits"]
        self.assertEqual(limits["status"], "allowed")
        self.assertEqual(limits["windows"]["five_hour"], {"utilization": 0.3, "resets_at": 1700000000})
        self.assertEqual(limits["windows"]["seven_day"]["utilization"], 0.1)
        d = m.get(s["id"])
        self.assertEqual(d["context_tokens"], 2 + 500 + 100 + 8, "the subagent's call does not count")
        self.assertEqual(d["context_window"], 1000000)
        self.assertFalse([e for e in d["log"] if e["kind"] in ("usage", "limits")])
        m.shutdown()
        self.assertTrue(_wait(lambda: m.get(s["id"])["state"] == "stopped"))
        again = self.manager(state_file=state)
        self.assertEqual(again.status()["limits"]["windows"]["five_hour"]["utilization"], 0.3)
        self.assertEqual(again.get(s["id"])["context_tokens"], 610)

    def test_stop_then_send_resumes_the_session_and_adds_up_the_cost(self) -> None:
        m = self.manager()
        s = m.create(text="hello")
        self.assertTrue(m.wait_idle(s["id"]))
        m.stop(s["id"])
        self.assertTrue(_wait(lambda: m.get(s["id"])["state"] == "stopped"))
        m.send(s["id"], "more")
        self.assertTrue(m.wait_idle(s["id"]))
        launches = self.launches()
        self.assertEqual(len(launches), 2)
        self.assertEqual(launches[1][-2:], ["--resume", "sess-1"])
        self.assertEqual(m.get(s["id"])["cost_usd"], 1.0)

    def test_implement_task_from_the_backlog(self) -> None:
        m = self.manager()
        s = m.create(task="TASK-002")
        self.assertEqual(s["title"], "TASK-002 · Second thing")
        self.assertTrue(m.wait_idle(s["id"]))
        self.assertEqual(m.get(s["id"])["log"][0]["text"], "/implement-task TASK-002")
        again = m.create(task="TASK-002")
        self.assertTrue(again["existing"])
        self.assertEqual(again["id"], s["id"])
        self.assertEqual(len(m.list()), 1)

    def test_task_validation(self) -> None:
        m = self.manager()
        for task, status in (("TASK-001", 409), ("TASK-003", 409), ("TASK-999", 404), ("rm -rf", 400), ("-x", 400)):
            with self.assertRaises(chat.ChatError) as ctx:
                m.create(task=task)
            self.assertEqual(ctx.exception.status, status, task)
        for text in ("", "   ", 5, "x" * (chat.MAX_TEXT + 1)):
            with self.assertRaises(chat.ChatError):
                m.create(text=text)
        self.assertEqual(self.launches(), [])

    def test_one_working_session_at_a_time(self) -> None:
        m = self.manager()
        a = m.create(text="hang")
        self.assertTrue(_wait(lambda: m.get(a["id"])["session_id"] == "sess-1"))
        self.assertEqual(m.get(a["id"])["state"], "working")
        self.assertIn("working", m.busy())
        with self.assertRaises(chat.ChatError) as ctx:
            m.create(text="other")
        self.assertEqual(ctx.exception.status, 409)
        with self.assertRaises(chat.ChatError):
            m.send(a["id"], "while busy")
        m.stop(a["id"])
        self.assertTrue(_wait(lambda: m.get(a["id"])["state"] == "stopped"))
        self.assertIsNone(m.busy())

    def test_starting_a_process_stops_the_idle_one_of_another_session(self) -> None:
        m = self.manager()
        a = m.create(text="one")
        self.assertTrue(m.wait_idle(a["id"]))
        b = m.create(text="two")
        self.assertTrue(m.wait_idle(b["id"]))
        self.assertTrue(_wait(lambda: m.get(a["id"])["state"] == "stopped"))
        self.assertEqual(m.get(b["id"])["state"], "idle")

    def test_refused_while_another_tool_edits_the_tree(self) -> None:
        m = self.manager()
        self.probe_message = "a unit catalog model job for leopard_2a4 is running"
        with self.assertRaises(chat.ChatError) as ctx:
            m.create(text="hi")
        self.assertEqual(ctx.exception.status, 409)
        self.assertIn("leopard_2a4", ctx.exception.message)

    def test_crash_marks_the_session_failed(self) -> None:
        m = self.manager()
        s = m.create(text="crash")
        self.assertTrue(_wait(lambda: m.get(s["id"])["state"] == "failed"))
        self.assertIn("code 3", m.get(s["id"])["error"])

    def test_history_survives_a_restart(self) -> None:
        state = self.root / ".devtools" / "chats.json"
        m = self.manager(state_file=state)
        s = m.create(text="hello")
        self.assertTrue(m.wait_idle(s["id"]))
        m.shutdown()
        self.assertTrue(_wait(lambda: m.get(s["id"])["state"] == "stopped"))
        again = self.manager(state_file=state)
        d = again.get(s["id"])
        self.assertEqual(d["state"], "stopped")
        self.assertEqual(d["session_id"], "sess-1")
        self.assertEqual(d["resume_command"], "claude --resume sess-1")
        again.send(s["id"], "back")
        self.assertTrue(again.wait_idle(s["id"]))
        self.assertEqual(self.launches()[-1][-2:], ["--resume", "sess-1"])

    def test_only_one_devtools_instance_owns_the_history(self) -> None:
        state = self.root / ".devtools" / "chats.json"
        first = chat.lock_history(state)
        self.assertIsNotNone(first)
        self.assertIsNone(chat.lock_history(state))
        off = chat.ChatManager(self.root, str(self.claude), unavailable="another devtools instance runs the chat")
        self.assertFalse(off.status()["available"])
        self.assertIn("another devtools", off.status()["hint"])
        first.close()
        again = chat.lock_history(state)
        self.assertIsNotNone(again)
        again.close()

    def test_without_claude_nothing_starts(self) -> None:
        m = chat.ChatManager(self.root, None)
        self.assertFalse(m.status()["available"])
        with self.assertRaises(chat.ChatError) as ctx:
            m.create(text="hi")
        self.assertEqual(ctx.exception.status, 503)


class ChatServerTest(ChatTestBase):
    def setUp(self) -> None:
        super().setUp()
        self.jobs = runner.JobRunner(self.root)
        self.chats = self.manager()
        self.httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.make_handler(self.root, {}, self.jobs, self.chats))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self) -> None:
        self.jobs.shutdown()
        self.httpd.shutdown()
        self.httpd.server_close()
        super().tearDown()

    def request(self, method: str, path: str, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.httpd.server_address[1], timeout=5)
        conn.request(method, path, body=None if body is None else json.dumps(body),
                     headers=headers if headers is not None else {"Content-Type": "application/json"})
        res = conn.getresponse()
        data = json.loads(res.read() or b"null")
        conn.close()
        return res.status, data

    def test_chat_round_trip(self) -> None:
        status, s = self.request("POST", "/api/chat", {"text": "hello"})
        self.assertEqual(status, 201)
        self.assertTrue(self.chats.wait_idle(s["id"]))
        status, d = self.request("GET", "/api/chat/" + s["id"])
        self.assertEqual(d["log"][-2]["text"], "echo: hello")
        status, listing = self.request("GET", "/api/chat")
        self.assertTrue(listing["available"])
        self.assertEqual([x["id"] for x in listing["sessions"]], [s["id"]])
        self.assertEqual(self.request("POST", "/api/chat/%s/send" % s["id"], {"text": "more"})[0], 200)
        self.assertEqual(self.request("POST", "/api/chat/%s/stop" % s["id"], {})[0], 200)
        self.assertEqual(self.request("GET", "/api/chat/busy")[1], {"busy": False, "what": ""})
        self.assertEqual(self.request("GET", "/api/chat/nope")[0], 404)
        status, task = self.request("POST", "/api/chat", {"task": "TASK-002"})
        self.assertEqual(status, 201)
        self.assertTrue(self.chats.wait_idle(task["id"]))
        self.assertEqual(self.request("POST", "/api/chat", {"task": "TASK-002"})[0], 200)
        self.assertEqual(self.request("POST", "/api/chat", {"task": "$(id)"})[0], 400)

    def test_cross_site_posts_and_foreign_hosts_are_refused(self) -> None:
        port = self.httpd.server_address[1]
        self.assertEqual(self.request("POST", "/api/chat", {"text": "x"}, {"Content-Type": "text/plain"})[0], 403)
        self.assertEqual(self.request("POST", "/api/chat", {"text": "x"},
                                      {"Content-Type": "application/json", "Origin": "http://evil.example"})[0], 403)
        self.assertEqual(self.request("POST", "/api/chat", {"text": "x"},
                                      {"Content-Type": "application/json", "Origin": "http://localhost:8766"})[0], 403)
        self.assertEqual(self.request("GET", "/api/chat", None, {"Host": "evil.example:%d" % port})[0], 403)
        self.assertEqual(self.launches(), [])


def _wait(predicate, timeout: float = 10.0) -> bool:
    import time

    end = time.time() + timeout
    while time.time() < end:
        if predicate():
            return True
        time.sleep(0.02)
    return False


if __name__ == "__main__":
    unittest.main()
