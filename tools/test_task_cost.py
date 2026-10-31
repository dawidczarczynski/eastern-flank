"""Tests for tools/task_cost.py. Run: python3 -m unittest discover -s tools -p 'test_task_cost.py'"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import task_cost  # noqa: E402

OPUS = "claude-opus-5-5"
SONNET = "claude-sonnet-5-5"


def command(name: str, args: str, ts: str) -> dict:
    text = "<command-message>%s</command-message>\n<command-name>/%s</command-name>\n<command-args>%s</command-args>" % (name, name, args)
    return {"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}}


def reply(msg_id: str, model: str, ts: str, inp: int = 0, write: int = 0, read: int = 0, out: int = 0) -> dict:
    usage = {"input_tokens": inp, "cache_creation_input_tokens": write, "cache_read_input_tokens": read, "output_tokens": out}
    return {"type": "assistant", "timestamp": ts, "message": {"id": msg_id, "model": model, "usage": usage,
                                                             "content": [{"type": "text", "text": "secret words"}]}}  # fmt: skip


class TaskCostTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def session(self, name: str, records: list, subagents: dict = None, junk: str = "") -> None:
        lines = [json.dumps(r) for r in records]
        if junk:
            lines.insert(1, junk)
        (self.dir / ("%s.jsonl" % name)).write_text("\n".join(lines) + "\n", encoding="utf-8")
        for agent, recs in (subagents or {}).items():
            folder = self.dir / name / "subagents"
            folder.mkdir(parents=True, exist_ok=True)
            (folder / ("agent-%s.jsonl" % agent)).write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")

    def test_task_ids_are_normalised(self) -> None:
        for arg in ("57", "057", "TASK 057", "task-057", "TASK-057", " Task-57 "):
            self.assertEqual(task_cost.normalise_task_id(arg), "TASK-057", arg)
        self.assertEqual(task_cost.normalise_task_id("TASK-089b"), "TASK-089b")
        self.assertEqual(task_cost.normalise_task_id("16a"), "TASK-016a")
        self.assertEqual(task_cost.normalise_task_id("TASK-089b then commit"), "TASK-089b", "first word")
        for arg in ("", "everything", "TASK-"):
            self.assertIsNone(task_cost.normalise_task_id(arg), arg)

    def test_weighting_by_model_and_kind(self) -> None:
        cost = task_cost.weighted_cost({OPUS: {"input": 1_000_000, "cache_write": 0, "cache_read": 2_000_000, "output": 0},
                                        SONNET: {"input": 0, "cache_write": 1_000_000, "cache_read": 0, "output": 1_000_000}})  # fmt: skip
        self.assertAlmostEqual(cost, 5.0 + 2 * 0.5 + 3.75 + 15.0)
        self.assertEqual(task_cost.weighted_cost({"<synthetic>": {"output": 10**9}}), 0.0)
        self.assertAlmostEqual(task_cost.weighted_cost({"claude-mystery-9": {"output": 1_000_000}}), 25.0, msg="unknown → opus")

    def test_main_session_and_subagents_are_summed_and_duplicates_counted_once(self) -> None:
        self.session("s1", [
            command("implement-task", "057", "2026-10-01T10:00:00Z"),
            reply("m1", OPUS, "2026-10-01T10:00:05Z", out=1_000_000),
            reply("m1", OPUS, "2026-10-01T10:00:05Z", out=1_000_000),  # same response, second content block
            reply("m2", OPUS, "2026-10-01T11:00:00Z", read=2_000_000),
        ], subagents={"a1": [reply("sa1", SONNET, "2026-10-01T10:10:00Z", out=1_000_000)]}, junk="{not json")  # fmt: skip
        entry = task_cost.scan(self.dir)["TASK-057"]
        self.assertAlmostEqual(entry["cost"], 25.0 + 1.0 + 15.0)
        self.assertEqual(entry["tokens"], {"input": 0, "cache_write": 0, "cache_read": 2_000_000, "output": 2_000_000})
        self.assertEqual(entry["models"], [OPUS, SONNET])
        self.assertEqual((entry["sessions"], entry["active_hours"]), (1, 1.0))
        self.assertEqual((entry["orchestrator"], entry["main_cost"]), ("opus", 26.0), "the subagent is not the orchestrator")
        self.assertAlmostEqual(task_cost.session_cost(self.dir, "s1"), 41.0)
        self.assertEqual(task_cost.session_cost(self.dir, "missing"), 0.0)

    def test_sessions_of_one_task_are_summed_and_free_chats_ignored(self) -> None:
        self.session("s1", [command("implement-task", "TASK 057", "2026-10-01T10:00:00Z"), reply("a", OPUS, "2026-10-01T10:01:00Z", out=1_000_000)])
        self.session("s2", [command("implement-task", "task-057", "2026-10-02T10:00:00Z"), reply("b", OPUS, "2026-10-02T10:01:00Z", out=1_000_000)])
        self.session("s3", [{"type": "user", "timestamp": "2026-10-03T10:00:00Z", "message": {"content": "just chatting"}},
                            reply("c", OPUS, "2026-10-03T10:01:00Z", out=1_000_000)])  # fmt: skip
        tasks = task_cost.scan(self.dir)
        self.assertEqual(list(tasks), ["TASK-057"])
        self.assertEqual((tasks["TASK-057"]["cost"], tasks["TASK-057"]["sessions"]), (50.0, 2))
        self.assertEqual((tasks["TASK-057"]["first"], tasks["TASK-057"]["last"]), ("2026-10-01T10:00:00Z", "2026-10-02T10:01:00Z"))

    def test_clear_and_a_second_task_split_one_session(self) -> None:
        self.session("s1", [
            command("implement-task", "036", "2026-10-01T10:00:00Z"),
            reply("a", OPUS, "2026-10-01T10:01:00Z", out=1_000_000),
            command("clear", "", "2026-10-01T11:00:00Z"),
            reply("b", OPUS, "2026-10-01T11:01:00Z", out=1_000_000),
            command("implement-task", "027", "2026-10-01T12:00:00Z"),
            reply("c", OPUS, "2026-10-01T12:01:00Z", out=2_000_000),
        ], subagents={"x": [reply("d", SONNET, "2026-10-01T10:30:00Z", out=1_000_000)],
                      "y": [reply("e", SONNET, "2026-10-01T12:30:00Z", out=1_000_000)]})  # fmt: skip
        tasks = task_cost.scan(self.dir)
        self.assertEqual({k: v["cost"] for k, v in tasks.items()}, {"TASK-027": 65.0, "TASK-036": 40.0})

    def test_output_is_deterministic_and_has_no_message_text(self) -> None:
        self.session("s1", [command("implement-task", "2", "2026-10-01T10:00:00Z"), reply("a", OPUS, "2026-10-01T10:01:00Z", out=10)])
        self.session("s0", [command("implement-task", "1", "2026-10-01T09:00:00Z"), reply("b", OPUS, "2026-10-01T09:01:00Z", out=10)])
        out = self.dir / "out" / "costs.json"
        task_cost.write(task_cost.scan(self.dir), out)
        first = out.read_text(encoding="utf-8")
        task_cost.write(task_cost.scan(self.dir), out)
        self.assertEqual(out.read_text(encoding="utf-8"), first)
        self.assertNotIn("secret", first)
        self.assertEqual(list(task_cost.load(out)), ["TASK-001", "TASK-002"])
        self.assertEqual(task_cost.load(self.dir / "nothing.json"), {})
        out.write_text(json.dumps({"tasks": {"TASK-001": "broken", "TASK-002": {"cost": 1.0}}}))
        self.assertEqual(list(task_cost.load(out)), ["TASK-002"], "malformed entries are dropped")

    def test_refresh_keeps_tasks_whose_transcripts_were_cleaned_up(self) -> None:
        out = self.dir / "costs.json"
        self.session("s1", [command("implement-task", "1", "2026-10-01T09:00:00Z"), reply("a", OPUS, "2026-10-01T09:01:00Z", out=1_000_000)])
        self.session("s2", [command("implement-task", "2", "2026-10-02T09:00:00Z"), reply("b", OPUS, "2026-10-02T09:01:00Z", out=1_000_000)])
        task_cost.refresh(self.dir, out)
        (self.dir / "s1.jsonl").unlink()  # Claude Code's cleanup
        self.session("s3", [command("implement-task", "2", "2026-10-03T09:00:00Z"), reply("c", OPUS, "2026-10-03T09:01:00Z", out=1_000_000)])
        tasks = task_cost.refresh(self.dir, out)
        self.assertEqual({k: v["cost"] for k, v in tasks.items()}, {"TASK-001": 25.0, "TASK-002": 50.0})
        self.assertEqual(task_cost.load(out), tasks)

    def test_project_dir_slug(self) -> None:
        self.assertEqual(task_cost.project_dir(Path("/home/x/my_repo.v2")).name, "-home-x-my-repo-v2")


if __name__ == "__main__":
    unittest.main()
