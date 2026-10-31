"""Tests for the devtools Claude chat. Run: python3 -m unittest discover -s tools/devtools -p 'test_*.py'"""
import http.client
import json
import shutil
import stat
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chat  # noqa: E402
import runner  # noqa: E402
import server  # noqa: E402

# Stands in for `claude -p --input-format stream-json --permission-prompt-tool stdio`: logs its argv, speaks the
# control protocol (initialize, can_use_tool, interrupt) and answers every other message with an echo.
#   "tool" / "question" → a permission prompt / AskUserQuestion, the turn reports the answer it got
#   "hang" → a turn that runs until it is interrupted;  "stuck" → one that ignores the interrupt
#   "crash" → exit 3;  "/compact" → slash command output
FAKE_CLAUDE = r'''#!%s
import json, sys, time
args = sys.argv[1:]
with open(%r, "a") as f:
    f.write(json.dumps(args) + "\n")
sid = args[args.index("--resume") + 1] if "--resume" in args else "sess-1"
cost = 0.0
def out(o):
    print(json.dumps(o), flush=True)
def finish(text):
    global cost
    cost += 0.5
    out({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "unifiedWindows": {
        "five_hour": {"utilization": 0.25 + cost / 10, "resetsAt": 1700000000}, "seven_day": {"utilization": 0.1, "resetsAt": 1700500000}}}})
    usage = {"input_tokens": 2, "cache_read_input_tokens": int(cost * 1000), "cache_creation_input_tokens": 100, "output_tokens": 8}
    out({"type": "assistant", "message": {"content": [{"type": "text", "text": text}], "usage": usage}})
    out({"type": "assistant", "parent_tool_use_id": "t1", "message": {"content": [], "usage": {"input_tokens": 99999}}})
    out({"type": "result", "result": "x", "is_error": False, "total_cost_usd": cost, "session_id": sid,
         "modelUsage": {"m": {"contextWindow": 200000}, "sub": {"contextWindow": 1000000}}})
REQUESTS = {
    "tool": {"subtype": "can_use_tool", "tool_name": "Bash", "input": {"command": "touch x"}, "permission_suggestions": [
        {"type": "addRules", "rules": [{"toolName": "Bash", "ruleContent": "touch x"}], "behavior": "allow", "destination": "localSettings"},
        {"type": "setMode", "mode": "acceptEdits", "destination": "session"}]},
    "question": {"subtype": "can_use_tool", "tool_name": "AskUserQuestion", "input": {"questions": [
        {"question": "Pick", "header": "P", "options": [{"label": "Red"}, {"label": "Blue"}], "multiSelect": False}]}},
}
for line in sys.stdin:
    m = json.loads(line)
    if m["type"] == "control_request":
        if m["request"]["subtype"] == "initialize":
            out({"type": "control_response", "response": {"subtype": "success", "request_id": m["request_id"], "response": {
                "commands": [{"name": "compact", "description": "Compact the conversation", "argumentHint": ""},
                             {"name": "implement-task", "description": "Carry out a task", "argumentHint": "TASK-001"}]}}})
        continue
    if m["type"] != "user":
        continue
    text = m["message"]["content"]
    out({"type": "system", "subtype": "init", "session_id": sid, "model": "fake"})
    if text == "hang":
        for raw in sys.stdin:
            msg = json.loads(raw)
            if msg["type"] == "control_request" and msg["request"]["subtype"] == "interrupt":
                break
            out({"type": "assistant", "message": {"content": [{"type": "text", "text": "noted: " + msg["message"]["content"]}]}})
        out({"type": "user", "message": {"content": [{"type": "text", "text": "[Request interrupted by user]"}]}})
        out({"type": "result", "is_error": True, "subtype": "error_during_execution", "total_cost_usd": cost, "session_id": sid})
        continue
    if text == "stuck":
        time.sleep(60)
    if text == "crash":
        sys.exit(3)
    if text == "agents":
        def sysev(sub, **kw):
            out(dict({"type": "system", "subtype": sub, "session_id": sid, "uuid": "u"}, **kw))
        sysev("task_started", task_id="fg", tool_use_id="t1", task_type="local_agent", subagent_type="gameplay-engineer",
              description="core rules", is_backgrounded=False, spawn_depth=1, prompt="long prompt")
        sysev("task_started", task_id="bg", tool_use_id="t2", task_type="local_agent", subagent_type="reviewer",
              description="review", is_backgrounded=True, spawn_depth=1)
        sysev("task_started", task_id="sh", task_type="local_bash", description="tools/check.sh", is_backgrounded=False,
              owned_by_subagent=True, parent_task_id="fg")
        sysev("task_progress", task_id="fg", description="Running tools/test.sh", last_tool_name="Bash",
              usage={"total_tokens": 1234, "tool_uses": 3, "duration_ms": 900})
        sysev("task_updated", task_id="fg", patch={"status": "completed", "end_time": 1})
    if text == "empty-turn":  # a background task's notice opens a turn with nothing in it
        finish("echo: " + text)
        out({"type": "system", "subtype": "init", "session_id": sid, "model": "fake"})
        out({"type": "result", "result": "", "is_error": False, "total_cost_usd": cost, "session_id": sid})
        continue
    if text == "/compact":
        out({"type": "user", "message": {"content": "<local-command-stdout>Compacted </local-command-stdout>"}})
        out({"type": "result", "result": "", "is_error": False, "total_cost_usd": cost, "session_id": sid})
        continue
    if text in REQUESTS:
        req = REQUESTS[text]
        out({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "tu1", "name": req["tool_name"], "input": req["input"]}]}})
        out({"type": "control_request", "request_id": "req-1", "request": req})
        reply = json.loads(sys.stdin.readline())["response"]["response"]
        text = reply["behavior"]
        if reply.get("updatedPermissions"):
            text += " rules=" + json.dumps([p["type"] for p in reply["updatedPermissions"]])
        if "answers" in reply.get("updatedInput", {}):
            text += " answers=" + json.dumps(reply["updatedInput"]["answers"])
        if reply["behavior"] == "deny":
            text += " message=" + reply["message"]
        out({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tu1", "content": text,
                                                        "is_error": reply["behavior"] == "deny"}]}})
    finish("echo: " + text)
'''

BACKLOG = """# Backlog

| ID | Title | Status | Depends on |
|---|---|---|---|
| [TASK-001](TASK-001-a.md) | First `thing` | 🔵 done | – |
| [TASK-002](TASK-002-b.md) | Second thing | 🟢 ready | TASK-001 |
| TASK-003 | Just an idea | 💡 idea | – |
"""


def _wait(predicate, timeout: float = 10.0) -> bool:
    end = time.time() + timeout
    while time.time() < end:
        if predicate():
            return True
        time.sleep(0.02)
    return False


class ChatTestBase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        (self.root / "docs" / "tasks").mkdir(parents=True)
        (self.root / "docs" / "tasks" / "BACKLOG.md").write_text(BACKLOG, encoding="utf-8")
        self.argv_log = self.root / "argv.log"
        self.claude = self.root / "fake-claude"
        self.claude.write_text(FAKE_CLAUDE % (sys.executable, str(self.argv_log)), encoding="utf-8")
        self.claude.chmod(self.claude.stat().st_mode | stat.S_IEXEC)
        self.managers = []

    def tearDown(self) -> None:
        for manager in self.managers:
            manager.shutdown()
        shutil.rmtree(self.root, ignore_errors=True)

    def manager(self, **kw) -> chat.ChatManager:
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

    def state(self, m: chat.ChatManager, sid: str) -> str:
        return m.get(sid)["state"]


class CommandTest(unittest.TestCase):
    def test_runs_like_the_ide_with_prompts_over_stdio(self) -> None:
        cmd = chat.build_command("claude")
        self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "auto")
        self.assertEqual(cmd[cmd.index("--permission-prompt-tool") + 1], "stdio")
        self.assertEqual(cmd[cmd.index("--input-format") + 1], "stream-json")
        for extra in ("--allowedTools", "--disallowedTools", "--append-system-prompt", "--dangerously-skip-permissions"):
            self.assertNotIn(extra, cmd)
        self.assertEqual(chat.build_command("claude", "abc-1")[-2:], ["--resume", "abc-1"])
        self.assertNotIn("--model", cmd, "free chats keep the human's default model")
        self.assertEqual(chat.build_command("claude", "", "sonnet")[-2:], ["--model", "sonnet"])
        with self.assertRaises(chat.ChatError):
            chat.build_command("claude", "--dangerously-skip-permissions")


def parse(msg: dict) -> list:
    return chat.claude_cli.parse_stream_line(json.dumps(msg), detail=True)


class StreamParseTest(unittest.TestCase):
    def test_tool_details_and_results(self) -> None:
        tool = parse({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "tu", "name": "Edit",
                      "input": {"file_path": "/a.gd", "old_string": "x" * 7000, "new_string": "y"}}]}})[0]
        self.assertEqual((tool["id"], tool["name"], tool["text"]), ("tu", "Edit", "Edit: /a.gd"))
        self.assertLess(len(tool["input"]["old_string"]), 6100)
        result = parse({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "tu",
                        "content": [{"type": "text", "text": "line 1\nline 2"}]}]}})[0]
        self.assertEqual(result, {"kind": "tool_result", "tool_use_id": "tu", "text": "line 1\nline 2", "is_error": False, "sub": False})

    def test_cli_notices(self) -> None:
        self.assertEqual(parse({"type": "user", "message": {"content": "<local-command-stdout>Compacted </local-command-stdout>"}})[0]["text"], "Compacted")
        self.assertIn("compacted", parse({"type": "user", "message": {"content": "This session is being continued from ..."}})[0]["text"])
        self.assertEqual(parse({"type": "user", "message": {"content": [{"type": "text", "text": "[Request interrupted by user]"}]}})[0]["text"], "interrupted")
        self.assertEqual(parse({"type": "control_request", "request_id": "r", "request": {}})[0]["kind"], "control")
        self.assertEqual(chat.claude_cli.parse_stream_line(json.dumps({"type": "control_request"})), [], "only in detail mode")

    def test_permission_refusals_are_shortened(self) -> None:
        def error(text: str) -> str:
            return chat.claude_cli.parse_stream_line(json.dumps(
                {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": True, "content": text}]}}))[0]["text"]
        self.assertEqual(error("Permission to use Bash has been denied because Claude Code is running in don't ask mode. ..."),
                         "denied: Bash (not on the allow-list)")
        self.assertEqual(error("Permission to use Bash with command git stash has been denied."), "denied: Bash git stash (deny rule)")
        self.assertEqual(error("Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Data Exfiltration]. If ..."),
                         "blocked by the auto mode classifier: Data Exfiltration")


class ChatManagerTest(ChatTestBase):
    def test_free_chat_keeps_one_process_across_messages(self) -> None:
        m = self.manager()
        s = m.create(text="hello")
        self.assertTrue(m.wait_state(s["id"], ("idle",)))
        d = m.get(s["id"])
        self.assertEqual(d["session_id"], "sess-1")
        self.assertEqual(d["cost_usd"], 0.5)
        self.assertEqual(d["changed_files"], [" M src/x.gd"])
        self.assertEqual(self.kinds(d), [("user", "hello"), ("text", "echo: hello"), ("turn", "")])
        m.send(s["id"], "again")
        self.assertTrue(_wait(lambda: m.get(s["id"])["cost_usd"] == 1.0 and self.state(m, s["id"]) == "idle"))
        d = m.get(s["id"], since=d["log_from"] + len(d["log"]))
        self.assertEqual(self.kinds(d), [("user", "again"), ("text", "echo: again"), ("turn", "")])
        self.assertEqual(len(self.launches()), 1)
        self.assertEqual(sum(1 for e in m.get(s["id"])["log"] if e["kind"] == "info"), 1, "init shown once per process")

    def test_an_empty_turn_adds_no_second_marker(self) -> None:
        m = self.manager()
        s = m.create(text="empty-turn")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn" and self.state(m, s["id"]) == "idle"))
        time.sleep(0.2)
        self.assertEqual([e["kind"] for e in m.get(s["id"])["log"]].count("turn"), 1)

    def test_slash_commands_come_from_initialize_and_run_as_messages(self) -> None:
        m = self.manager()
        s = m.create(text="/compact")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        self.assertEqual([c["name"] for c in m.status()["commands"]], ["compact", "implement-task"])
        self.assertEqual(m.status()["commands"][1]["hint"], "TASK-001")
        self.assertIn(("info", "Compacted"), [(e["kind"], e.get("text")) for e in m.get(s["id"])["log"]])

    def test_permission_prompt_allow_always_and_deny(self) -> None:
        m = self.manager()
        s = m.create(text="tool")
        self.assertTrue(m.wait_state(s["id"], ("asking",)))
        d = m.get(s["id"])
        [req] = d["pending_requests"]
        self.assertEqual((req["tool"], req["input"]), ("Bash", {"command": "touch x"}))
        self.assertEqual([x["type"] for x in req["suggestions"]], ["addRules"], "only rule suggestions, no mode switch")
        ask = [e for e in d["log"] if e["kind"] == "ask"][0]
        self.assertEqual((ask["text"], ask["always"]), ("Bash: touch x", True))
        m.answer(s["id"], req["request_id"], "always")
        self.assertTrue(_wait(lambda: 'echo: allow rules=["addRules"]' in [e.get("text") for e in m.get(s["id"])["log"]]))
        with self.assertRaises(chat.ChatError):
            m.answer(s["id"], req["request_id"], "allow")  # answered already
        self.assertTrue(m.wait_state(s["id"], ("idle",)))
        m.send(s["id"], "tool")
        self.assertTrue(m.wait_state(s["id"], ("asking",)))
        rid = m.get(s["id"])["pending_requests"][0]["request_id"]
        with self.assertRaises(chat.ChatError):
            m.answer(s["id"], rid, "maybe")
        m.answer(s["id"], rid, "deny", message="use git instead")
        self.assertTrue(_wait(lambda: "echo: deny message=use git instead" in [e.get("text") for e in m.get(s["id"])["log"]]))

    def test_ask_user_question_answers(self) -> None:
        m = self.manager()
        s = m.create(text="question")
        self.assertTrue(m.wait_state(s["id"], ("asking",)))
        rid = m.get(s["id"])["pending_requests"][0]["request_id"]
        for bad in (None, {}, {"Other question": "x"}, {"Pick": ""}, {"Pick": 3}):
            with self.assertRaises(chat.ChatError):
                m.answer(s["id"], rid, "allow", answers=bad)
        m.answer(s["id"], rid, "allow", answers={"Pick": "Blue"})
        self.assertTrue(_wait(lambda: 'echo: allow answers={"Pick": "Blue"}' in [e.get("text") for e in m.get(s["id"])["log"]]))
        self.assertIn({"Pick": "Blue"}, [e.get("answers") for e in m.get(s["id"])["log"]])

    def test_messages_while_working_and_stop_interrupts_without_killing(self) -> None:
        m = self.manager()
        s = m.create(text="hang")
        self.assertTrue(_wait(lambda: self.state(m, s["id"]) == "working" and m.get(s["id"])["session_id"]))
        m.send(s["id"], "meanwhile")  # folded into the running turn
        self.assertTrue(_wait(lambda: "noted: meanwhile" in [e.get("text") for e in m.get(s["id"])["log"]]))
        m.stop(s["id"])
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        d = m.get(s["id"])
        self.assertEqual(d["state"], "idle")
        self.assertIn(("info", "interrupted"), [(e["kind"], e.get("text")) for e in d["log"]])
        self.assertTrue(d["log"][-1]["is_error"])
        m.send(s["id"], "after")
        self.assertTrue(_wait(lambda: "echo: after" in [e.get("text") for e in m.get(s["id"])["log"]]))
        self.assertEqual(len(self.launches()), 1, "same process after the interrupt")

    def test_stop_kills_a_turn_that_ignores_the_interrupt(self) -> None:
        m = self.manager()
        s = m.create(text="stuck")
        self.assertTrue(_wait(lambda: m.get(s["id"])["session_id"] == "sess-1"))
        with mock.patch.object(chat, "INTERRUPT_GRACE", 0.3):
            m.stop(s["id"])
            self.assertTrue(m.wait_state(s["id"], ("stopped",)))
        m.send(s["id"], "back")
        self.assertTrue(_wait(lambda: "echo: back" in [e.get("text") for e in m.get(s["id"])["log"]]))
        self.assertEqual(self.launches()[-1][-2:], ["--resume", "sess-1"])

    def test_parallel_sessions_and_idle_process_cap(self) -> None:
        m = self.manager()
        a = m.create(text="hang")
        b = m.create(text="hello")  # another chat may work at the same time, as in the IDE
        self.assertTrue(_wait(lambda: m.get(b["id"])["log"][-1]["kind"] == "turn"))
        self.assertEqual(self.state(m, a["id"]), "working")
        m.stop(a["id"])
        self.assertTrue(_wait(lambda: m.get(a["id"])["log"][-1]["kind"] == "turn"))
        with mock.patch.object(chat, "MAX_IDLE_PROCESSES", 1):
            c = m.create(text="third")
            self.assertTrue(_wait(lambda: m.get(c["id"])["log"][-1]["kind"] == "turn"))
            self.assertTrue(_wait(lambda: [self.state(m, x["id"]) for x in (a, b)].count("stopped") == 2))

    def test_implement_task_from_the_backlog(self) -> None:
        m = self.manager()
        s = m.create(task="TASK-002")
        self.assertEqual(s["title"], "TASK-002 · Second thing")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        self.assertEqual(m.get(s["id"])["log"][0]["text"], "/implement-task TASK-002")
        argv = self.launches()[-1]
        self.assertEqual(argv[argv.index("--model") + 1], "sonnet", "the orchestrator always runs on sonnet")
        again = m.create(task="TASK-002")
        self.assertTrue(again["existing"])
        self.assertEqual(again["id"], s["id"])
        self.assertEqual(len(m.list()), 1)

    def test_design_an_idea_with_the_game_designer(self) -> None:
        m = self.manager()
        s = m.create(task="TASK-003", design=True)
        self.assertEqual(s["kind"], "design")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        self.assertIn("game-designer agent", m.get(s["id"])["log"][0]["text"])
        self.assertIn("TASK-003", m.get(s["id"])["log"][0]["text"])
        self.assertTrue(m.create(task="TASK-003", design=True)["existing"])
        with self.assertRaises(chat.ChatError):
            m.create(task="TASK-002", design=True)  # not an idea

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

    def test_crash_marks_the_session_failed(self) -> None:
        m = self.manager()
        s = m.create(text="crash")
        self.assertTrue(m.wait_state(s["id"], ("failed",)))
        self.assertIn("code 3", m.get(s["id"])["error"])

    def test_subagents_and_background_tasks_are_followed(self) -> None:
        m = self.manager()
        s = m.create(text="agents")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        d = m.get(s["id"])
        tasks = {t["id"]: t for t in d["tasks"]}
        self.assertEqual(sorted(tasks), ["bg", "fg"], "a subagent's own foreground command is not listed")
        self.assertEqual((tasks["fg"]["type"], tasks["fg"]["description"], tasks["fg"]["status"]), ("gameplay-engineer", "core rules", "completed"))
        self.assertEqual((tasks["fg"]["activity"], tasks["fg"]["tokens"], tasks["fg"]["tool_uses"]), ("Running tools/test.sh", 1234, 3))
        self.assertEqual((tasks["bg"]["status"], tasks["bg"]["background"]), ("running", True), "outlives the turn")
        self.assertEqual((d["state"], d["agents"]), ("idle", 1))
        self.assertFalse([e for e in d["log"] if e["kind"] == "task"])
        with mock.patch.object(chat, "TASK_SHOWN_FOR", 0.0):
            time.sleep(0.01)
            self.assertEqual([t["id"] for t in m.get(s["id"])["tasks"]], ["bg"], "finished ones drop out")
        m.shutdown()
        self.assertTrue(_wait(lambda: m.get(s["id"])["tasks"] == []), "the process took its subagents with it")

    def test_usage_limits_and_context_are_tracked_not_logged(self) -> None:
        state = self.root / ".devtools" / "chats.json"
        m = self.manager(state_file=state)
        self.assertIsNone(m.status()["limits"])
        s = m.create(text="hello")
        self.assertTrue(_wait(lambda: m.get(s["id"])["log"][-1]["kind"] == "turn"))
        limits = m.status()["limits"]
        self.assertEqual(limits["status"], "allowed")
        self.assertEqual(limits["windows"]["five_hour"], {"utilization": 0.3, "resets_at": 1700000000})
        d = m.get(s["id"])
        self.assertEqual(d["context_tokens"], 2 + 500 + 100 + 8, "the subagent's call does not count")
        self.assertEqual(d["context_window"], 1000000)
        self.assertFalse([e for e in d["log"] if e["kind"] in ("usage", "limits", "control")])
        m.shutdown()
        self.assertTrue(m.wait_state(s["id"], ("stopped",)))
        again = self.manager(state_file=state)
        self.assertEqual(again.status()["limits"]["windows"]["five_hour"]["utilization"], 0.3)
        self.assertEqual(again.status()["commands"][0]["name"], "compact")
        d = again.get(s["id"])
        self.assertEqual((d["state"], d["session_id"], d["context_tokens"]), ("stopped", "sess-1", 610))
        self.assertEqual(d["resume_command"], "claude --resume sess-1")
        again.send(s["id"], "back")
        self.assertTrue(_wait(lambda: "echo: back" in [e.get("text") for e in again.get(s["id"])["log"]]))
        self.assertEqual(self.launches()[-1][-2:], ["--resume", "sess-1"])

    def calibrated(self) -> chat.ChatManager:
        projects = self.root / "projects"
        projects.mkdir()
        reply = {"type": "assistant", "message": {"id": "m1", "model": "claude-opus-5-5", "usage": {"output_tokens": 1000000}}}
        (projects / "sess-1.jsonl").write_text(json.dumps(reply) + "\n", encoding="utf-8")
        self.calibration = self.root / "docs" / "tasks" / "usage_calibration.jsonl"
        self.limits_file = self.root / ".devtools" / "limits.json"
        return self.manager(calibration_file=self.calibration, limits_file=self.limits_file, projects_dir=projects)

    def samples(self) -> list:
        return chat.usage_forecast.load_samples(self.calibration)

    def test_task_turns_record_calibration_samples(self) -> None:
        m = self.calibrated()
        s = m.create(task="TASK-002")
        self.assertTrue(_wait(lambda: len(self.samples()) == 1))
        first = self.samples()[0]
        self.assertEqual((first["task"], first["chat"], first["cost_start"], first["cost_end"]), ("TASK-002", s["id"], 0.0, 25.0))
        self.assertEqual((first["windows"], first["parallel"], first["stale"]), ({}, False, False), "no limits known at the start")
        self.assertEqual(json.loads(self.limits_file.read_text())["windows"]["five_hour"]["utilization"], 0.3)
        m.send(s["id"], "again")
        self.assertTrue(_wait(lambda: len(self.samples()) == 2))
        second = self.samples()[1]
        self.assertEqual((second["cost_start"], second["cost_end"]), (25.0, 25.0), "read from the transcript")
        self.assertEqual(second["windows"]["five_hour"], {"start": 0.3, "end": 0.35, "resets_start": 1700000000, "resets_end": 1700000000})
        free = m.create(text="hello")
        self.assertTrue(_wait(lambda: m.get(free["id"])["log"][-1]["kind"] == "turn"))
        self.assertEqual(len(self.samples()), 2, "free chats record nothing")

    def test_a_session_working_in_parallel_taints_the_sample(self) -> None:
        m = self.calibrated()
        s = m.create(task="TASK-002")
        self.assertTrue(_wait(lambda: len(self.samples()) == 1))
        m.send(s["id"], "hang")
        self.assertTrue(_wait(lambda: self.state(m, s["id"]) == "working"))
        free = m.create(text="hello")  # starts while the task's turn runs
        self.assertTrue(_wait(lambda: m.get(free["id"])["log"][-1]["kind"] == "turn"))
        m.stop(s["id"])
        self.assertTrue(_wait(lambda: len(self.samples()) == 2))
        self.assertEqual([x["parallel"] for x in self.samples()], [False, True])
        busy = m.create(text="hang")
        self.assertTrue(_wait(lambda: self.state(m, busy["id"]) == "working"))
        m.send(s["id"], "late")  # starts while another session works
        self.assertTrue(_wait(lambda: len(self.samples()) == 3))
        self.assertTrue(self.samples()[2]["parallel"])
        m.stop(busy["id"])

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
        status, s = self.request("POST", "/api/chat", {"text": "tool"})
        self.assertEqual(status, 201)
        self.assertTrue(self.chats.wait_state(s["id"], ("asking",)))
        status, d = self.request("GET", "/api/chat/" + s["id"])
        rid = d["pending_requests"][0]["request_id"]
        self.assertEqual(self.request("POST", "/api/chat/%s/answer" % s["id"], {"request_id": rid, "behavior": "nope"})[0], 400)
        self.assertEqual(self.request("POST", "/api/chat/%s/answer" % s["id"], {"request_id": rid, "behavior": "allow"})[0], 200)
        self.assertTrue(_wait(lambda: self.chats.get(s["id"])["log"][-1]["kind"] == "turn"))
        status, listing = self.request("GET", "/api/chat")
        self.assertTrue(listing["available"])
        self.assertEqual(listing["permission_mode"], "auto")
        self.assertEqual([x["id"] for x in listing["sessions"]], [s["id"]])
        self.assertEqual(self.request("POST", "/api/chat/%s/send" % s["id"], {"text": "more"})[0], 200)
        self.assertEqual(self.request("POST", "/api/chat/%s/stop" % s["id"], {})[0], 200)
        self.assertEqual(self.request("GET", "/api/chat/nope")[0], 404)
        status, task = self.request("POST", "/api/chat", {"task": "TASK-002"})
        self.assertEqual(status, 201)
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


if __name__ == "__main__":
    unittest.main()
