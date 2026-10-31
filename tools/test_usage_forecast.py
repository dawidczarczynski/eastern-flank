"""Tests for tools/usage_forecast.py. Run: python3 -m unittest discover -s tools -p 'test_usage_forecast.py'"""
import json
import random
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import usage_forecast as uf  # noqa: E402

RESET = 2_000_000_000.0  # far in the future


def sample(chat: str, cost: float, pp: float, start: float = 0.2, parallel: bool = False, reset_end: float = RESET,
           stale: bool = False) -> dict:  # fmt: skip
    return {"task": "TASK-001", "chat": chat, "start": 1000.0, "end": 2000.0, "cost_start": 1.0, "cost_end": 1.0 + cost,
            "parallel": parallel, "stale": stale,
            "windows": {"five_hour": {"start": start, "end": start + pp / 100.0, "resets_start": RESET, "resets_end": reset_end},
                        "seven_day": {"start": 0.1, "end": 0.1 + pp / 500.0, "resets_start": RESET, "resets_end": RESET}}}  # fmt: skip


class CalibrationTest(unittest.TestCase):
    def test_reset_parallel_and_stale_samples_are_dropped(self) -> None:
        self.assertTrue(uf.usable(sample("a", 1.0, 5.0), "five_hour"))
        self.assertFalse(uf.usable(sample("a", 1.0, 5.0, reset_end=RESET + 18000), "five_hour"), "reset inside")
        self.assertTrue(uf.usable(sample("a", 1.0, 5.0, reset_end=RESET + 18000), "seven_day"), "only that window")
        late = sample("a", 1.0, 5.0)
        late["end"] = RESET + 1  # the reset time passed although the CLI didn't report a new window yet
        self.assertFalse(uf.usable(late, "five_hour"))
        self.assertFalse(uf.usable(sample("a", 1.0, 5.0, parallel=True), "five_hour"), "another session worked")
        self.assertFalse(uf.usable(sample("a", 1.0, 5.0, stale=True), "five_hour"), "no fresh limits")
        self.assertFalse(uf.usable(sample("a", 0.0, 5.0), "five_hour"), "no cost")
        missing = sample("a", 1.0, 5.0)
        del missing["windows"]["five_hour"]
        self.assertFalse(uf.usable(missing, "five_hour"))

    def test_fit_recovers_the_ratio(self) -> None:
        rng = random.Random(7)
        samples = []
        for i in range(8):  # 8 sessions of 3 turns, 4 % per cost unit ± 15 % noise, plus junk the fit must ignore
            for _ in range(3):
                cost = rng.uniform(0.5, 3.0)
                samples.append(sample("chat-%d" % i, cost, cost * 4.0 * rng.uniform(0.85, 1.15)))
        samples += [sample("x", 1.0, 40.0, parallel=True), sample("y", 1.0, 40.0, reset_end=RESET + 1)]
        result = uf.fit(samples, "five_hour")
        self.assertEqual(result["sessions"], 8)
        self.assertAlmostEqual(result["percent_per_cost"], 4.0, delta=0.4)
        self.assertAlmostEqual(uf.fit(samples, "seven_day")["percent_per_cost"], 0.8, delta=0.08)

    def test_too_few_sessions_or_too_small_rises_stay_uncalibrated(self) -> None:
        four = [sample("c%d" % i, 1.0, 4.0) for i in range(uf.MIN_SAMPLES - 1)]
        self.assertEqual(uf.fit(four, "five_hour"), {"percent_per_cost": None, "sessions": uf.MIN_SAMPLES - 1})
        tiny = [sample("c%d" % i, 0.1, 1.0) for i in range(10)]
        self.assertIsNone(uf.fit(tiny, "five_hour")["percent_per_cost"], "rises under MIN_DELTA_PP")
        summed = [sample("c%d" % (i // 2), 0.25, 1.0) for i in range(10)]
        self.assertEqual(uf.fit(summed, "five_hour")["sessions"], 5, "turns of one session are summed")

    def test_samples_file_round_trip_and_live_limits(self) -> None:
        folder = Path(tempfile.mkdtemp())
        try:
            path = folder / "cal.jsonl"
            uf.append_sample(path, sample("a", 1.0, 5.0))
            with path.open("a") as handle:
                handle.write("garbage\n")
            uf.append_sample(path, sample("b", 1.0, 5.0))
            self.assertEqual([s["chat"] for s in uf.load_samples(path)], ["a", "b"])
            self.assertEqual(uf.calibration(folder / "none.jsonl")["five_hour"]["percent_per_cost"], None)
            limits = folder / "limits.json"
            limits.write_text(json.dumps({"updated": 150, "windows": {"five_hour": {"utilization": 0.9, "resets_at": 500},
                                                      "seven_day": {"utilization": 0.3, "resets_at": 100}}}))  # fmt: skip
            self.assertEqual(uf.current_limits(limits, now=200), {"five_hour": {"utilization": 0.9, "resets_at": 500.0}})
            self.assertEqual(uf.current_limits(folder / "none.json"), {})
            self.assertEqual(uf.current_limits(limits, now=150 + uf.LIMITS_MAX_AGE + 1), {}, "too old to be live")
        finally:
            shutil.rmtree(folder)


def task_text(boxes: int, filler: int = 0) -> str:
    return "# T\n\n## Acceptance criteria\n\n" + "- [ ] criterion\n" * boxes + "x" * filler


def row(task_id: str, status: str, model: str = "sonnet", layers: str = "core") -> dict:
    return {"id": task_id, "status": status, "model": model, "layers": layers}


class ForecastTest(unittest.TestCase):
    def setUp(self) -> None:
        # four finished sonnet logic tasks (cost 1, 2, 3, 4 with 4 boxes each), two opus view tasks
        self.rows = [row("TASK-%03d" % i, "done") for i in range(1, 5)]
        self.rows += [row("TASK-010", "done", "opus", "presentation"), row("TASK-011", "to playtest", "opus", "presentation")]
        self.texts = {r["id"]: task_text(4) for r in self.rows}
        self.costs = {"TASK-%03d" % i: {"cost": float(i), "sessions": 1, "active_hours": 1.0, "orchestrator": "opus"} for i in range(1, 5)}
        self.costs.update({"TASK-010": {"cost": 10.0}, "TASK-011": {"cost": 20.0}})

    def usage(self, extra_rows: list, extra_texts: dict, ratios: dict = None, limits: dict = None, costs: dict = None) -> dict:
        texts = dict(self.texts, **extra_texts)
        return uf.usage_rows(self.rows + extra_rows, texts, dict(self.costs, **(costs or {})), ratios or {}, limits or {})

    def test_layer_groups(self) -> None:
        self.assertEqual(uf.layer_group("core + ai"), "logic")
        self.assertEqual(uf.layer_group("presentation (HUD), scenes"), "view")
        self.assertEqual(uf.layer_group("core (rules) + presentation"), "logic+view")
        self.assertEqual(uf.layer_group("tools (Python stdlib)"), "tools")
        self.assertEqual(uf.layer_group(""), "other")

    def test_forecast_from_the_same_group_scaled_by_size(self) -> None:
        out = self.usage([row("TASK-020", "ready")], {"TASK-020": task_text(4)})
        f = out["TASK-020"]
        self.assertEqual((f["kind"], f["low_confidence"], f["group"]), ("forecast", False, "sonnet · logic"))
        self.assertEqual((f["low"], f["mid"], f["high"]), (1.75, 2.5, 3.25))
        self.assertEqual([b["id"] for b in f["basis"]], ["TASK-001", "TASK-002", "TASK-003", "TASK-004"])
        big = self.usage([row("TASK-020", "ready")], {"TASK-020": task_text(8, filler=len(task_text(4)))})["TASK-020"]
        self.assertEqual((big["scale"], big["mid"]), (2.0, 5.0), "double the boxes and the text, clamped at 2×")
        self.assertEqual(out["TASK-001"]["kind"], "actual")
        self.assertEqual([out["TASK-00%d" % i]["class"] for i in range(1, 5)], ["S", "S", "M", "L"], "quartiles of 1, 2, 3, 4, 10, 20")
        self.assertEqual(out["TASK-011"]["class"], "XL")

    def test_only_sonnet_orchestrated_history_once_there_is_enough(self) -> None:
        rows = [row("TASK-%03d" % i, "done") for i in range(100, 100 + uf.MIN_ORCHESTRATED)]
        costs = {r["id"]: {"cost": 10.0, "orchestrator": "sonnet"} for r in rows}
        texts = {r["id"]: task_text(4) for r in rows}
        f = self.usage(rows + [row("TASK-020", "ready")], dict(texts, **{"TASK-020": task_text(4)}), costs=costs)["TASK-020"]
        self.assertEqual((f["history"], f["mid"], len(f["basis"])), ("sonnet", 10.0, uf.MIN_ORCHESTRATED), "the opus-run 1–4 are left out")
        fewer = self.usage(rows[1:] + [row("TASK-020", "ready")], dict(texts, **{"TASK-020": task_text(4)}), costs=costs)["TASK-020"]
        self.assertEqual(fewer["history"], "all")
        self.assertEqual(len(fewer["basis"]), 4 + uf.MIN_ORCHESTRATED - 1, "same group, every orchestrator")

    def test_small_group_falls_back_to_all_tasks_with_low_confidence(self) -> None:
        f = self.usage([row("TASK-020", "idea", "opus", "presentation")], {"TASK-020": task_text(4)})["TASK-020"]
        self.assertTrue(f["low_confidence"], "only two opus view tasks")
        self.assertEqual(len(f["basis"]), 6)
        no_file = self.usage([{"id": "TASK-021", "status": "idea", "model": "", "layers": ""}], {})["TASK-021"]
        self.assertEqual((no_file["low_confidence"], no_file["scale"]), (True, 1.0))
        self.assertEqual(uf.usage_rows([row("TASK-020", "ready")], {}, {}, {}, {}), {}, "nothing finished yet")

    def test_in_progress_subtracts_what_was_spent(self) -> None:
        f = self.usage([row("TASK-020", "in progress")], {"TASK-020": task_text(4)}, costs={"TASK-020": {"cost": 2.0}})["TASK-020"]
        self.assertEqual((f["low"], f["mid"], f["high"], f["spent"]), (0.0, 0.5, 1.25, 2.0))
        self.assertNotIn("TASK-020", [b["id"] for b in f["basis"]])

    def test_percentages_and_the_fit_warning(self) -> None:
        ratios = {"five_hour": 10.0, "seven_day": 2.0}
        limits = {"five_hour": {"utilization": 0.8, "resets_at": 1234.0}}
        out = self.usage([row("TASK-020", "ready")], {"TASK-020": task_text(4)}, ratios=ratios, limits=limits)
        f = out["TASK-020"]
        self.assertEqual(f["pct"], {"five_hour": [17.5, 32.5], "seven_day": [3.5, 6.5]})
        self.assertEqual(f["wont_fit"], 1234.0, "32.5 % > the 20 % left")
        self.assertEqual(out["TASK-002"]["pct"], {"five_hour": 20.0, "seven_day": 4.0})
        roomy = self.usage([row("TASK-020", "ready")], {"TASK-020": task_text(4)}, ratios=ratios,
                           limits={"five_hour": {"utilization": 0.1, "resets_at": 1234.0}})["TASK-020"]  # fmt: skip
        self.assertNotIn("wont_fit", roomy)
        uncalibrated = self.usage([row("TASK-020", "ready")], {"TASK-020": task_text(4)}, limits=limits)["TASK-020"]
        self.assertEqual(uncalibrated["pct"], {})
        self.assertNotIn("wont_fit", uncalibrated, "no marker without percentages")


if __name__ == "__main__":
    unittest.main()
