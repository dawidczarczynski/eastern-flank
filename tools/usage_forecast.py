"""Usage forecast per backlog task: calibration of weighted cost → % of the subscription's windows, and the
expected cost of open tasks from finished ones. Python 3.8, stdlib only.

Calibration (recorded by the devtools chat, tools/devtools/chat.py): one sample per turn of a task session -
the windows' utilization (0-1) and the session's weighted cost (tools/task_cost.py) at the start and the end of
the turn - appended to docs/tasks/usage_calibration.jsonl. A sample is unusable when a window reset falls inside
it, when another devtools session worked at the same time (utilization is account-wide), or when the CLI did not
report fresh limits during the turn. Usable samples are summed per chat session; a session whose utilization
rose by at least MIN_DELTA_PP points gives one ratio Δ% / Δcost, and the window's `percent_per_cost` is the
median of those ratios once there are MIN_SAMPLES of them (before that the window is "uncalibrated"). IDE
sessions devtools can't see still add noise - the median keeps single outliers out.

Forecast: the history is the finished tasks whose orchestrator (main session) ran on ORCHESTRATOR, as every new
task will - opus orchestrators made a task's cost differently shaped - once there are MIN_ORCHESTRATED of them;
before that all finished tasks (`history: "all"`). A task's comparable tasks are the ones in that history (with a measured cost) of the same model (the task's
**Model** line, default sonnet) and layer group (**Layers**: logic, view, logic+view, tools, other); fewer than
MIN_COMPARABLE of them → all finished tasks, marked low confidence. The range is the 25th-75th percentile of
their costs (point: the median), scaled by the task's size relative to theirs: the geometric mean of the
acceptance-criteria checkbox ratio and the task file length ratio against the comparables' medians, clamped to
SCALE_LIMITS. An `in progress` task shows the forecast minus what it already spent, floored at 0.
"""
from __future__ import annotations

import json
import math
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

WINDOWS = ("five_hour", "seven_day")
MIN_SAMPLES = 5  # calibrated sessions per window before percentages are shown
MIN_DELTA_PP = 2.0  # a session's utilization rise (percentage points) needed to count
MIN_COMPARABLE = 3
ORCHESTRATOR = "sonnet"  # what /implement-task runs on (its skill's `model`, devtools `--model`)
MIN_ORCHESTRATED = 10  # finished tasks with that orchestrator before only they are compared
LIMITS_MAX_AGE = 30 * 60  # seconds: older stored limits are not "live" (other sessions may have used the window)
SCALE_LIMITS = (0.5, 2.0)
FINISHED = ("done", "to playtest")
FORECAST = ("ready", "blocked", "idea", "in progress")
DEFAULT_MODEL = "sonnet"
CLASSES = ("S", "M", "L", "XL")
CHECKBOX = re.compile(r"^\s*[-*] \[[ xX]\]", re.MULTILINE)
LOGIC = re.compile(r"\b(core|ai)\b", re.I)
VIEW = re.compile(r"\b(presentation|scenes?|shaders?|hud|ui|models?)\b", re.I)
TOOLS = re.compile(r"\b(tools?|docs?)\b", re.I)


# ---- calibration


def _delta(sample: Dict[str, Any], window: str) -> Optional[Tuple[float, float]]:
    """(Δ percentage points, Δ cost) of a usable sample, else None."""
    if sample.get("parallel") or sample.get("stale"):
        return None
    w = (sample.get("windows") or {}).get(window)
    if not isinstance(w, dict):
        return None
    start, end, reset_start, reset_end = w.get("start"), w.get("end"), w.get("resets_start"), w.get("resets_end")
    if not all(isinstance(v, (int, float)) for v in (start, end, reset_start, reset_end)):
        return None
    if reset_start != reset_end or reset_start <= float(sample.get("end") or 0):
        return None  # the window reset inside the sample
    cost = float(sample.get("cost_end") or 0) - float(sample.get("cost_start") or 0)
    if cost <= 0 or end < start:
        return None
    return (end - start) * 100.0, cost


def usable(sample: Dict[str, Any], window: str) -> bool:
    return _delta(sample, window) is not None


def fit(samples: List[Dict[str, Any]], window: str) -> Dict[str, Any]:
    """`{"percent_per_cost": float | None, "sessions": n}`: median ratio over chat sessions (usable samples summed)."""
    sums: Dict[str, List[float]] = {}
    for sample in samples:
        delta = _delta(sample, window)
        if delta is None:
            continue
        acc = sums.setdefault(str(sample.get("chat") or sample.get("task") or ""), [0.0, 0.0])
        acc[0] += delta[0]
        acc[1] += delta[1]
    ratios = sorted(pp / cost for pp, cost in sums.values() if pp >= MIN_DELTA_PP and cost > 0)
    return {"percent_per_cost": _median(ratios) if len(ratios) >= MIN_SAMPLES else None, "sessions": len(ratios)}


def load_samples(path: Path) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return out
    for line in lines:
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            out.append(item)
    return out


def append_sample(path: Path, sample: Dict[str, Any]) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with Path(path).open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(sample, sort_keys=True) + "\n")


def calibration(path: Path) -> Dict[str, Dict[str, Any]]:
    samples = load_samples(path)
    return {window: fit(samples, window) for window in WINDOWS}


def current_limits(path: Path, now: Optional[float] = None) -> Dict[str, Dict[str, float]]:
    """The windows devtools stored last (`.devtools/limits.json`) that have not reset since: name → {utilization,
    resets_at}. {} without the file or when the values are older than LIMITS_MAX_AGE."""
    now = time.time() if now is None else now
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict) or not isinstance(data.get("updated"), (int, float)) or now - data["updated"] > LIMITS_MAX_AGE:
        return {}
    out: Dict[str, Dict[str, float]] = {}
    for name, w in ((data or {}).get("windows") or {}).items():
        if isinstance(w, dict) and isinstance(w.get("utilization"), (int, float)) and isinstance(w.get("resets_at"), (int, float)):
            if w["resets_at"] > now:
                out[name] = {"utilization": float(w["utilization"]), "resets_at": float(w["resets_at"])}
    return out


# ---- forecast


def _median(values: List[float]) -> float:
    return _percentile(values, 50)


def _percentile(values: List[float], pct: float) -> float:
    """Linear interpolation between the closest ranks."""
    ordered = sorted(values)
    if not ordered:
        return 0.0
    pos = (len(ordered) - 1) * pct / 100.0
    low = int(math.floor(pos))
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (pos - low)


def layer_group(layers: str) -> str:
    logic, view = bool(LOGIC.search(layers)), bool(VIEW.search(layers))
    if logic and view:
        return "logic+view"
    if logic:
        return "logic"
    if view:
        return "view"
    return "tools" if TOOLS.search(layers) else "other"


def features(row: Dict[str, Any], text: str) -> Dict[str, Any]:
    """What the forecast compares: model, layer group, checkbox count and length of the task file."""
    return {"model": row.get("model") or DEFAULT_MODEL, "group": layer_group(row.get("layers") or ""),
            "checkboxes": len(CHECKBOX.findall(text)), "chars": len(text)}  # fmt: skip


def size_classes(costs: List[float]) -> List[float]:
    """Upper bounds of S, M, L (quartiles of the finished tasks' costs); above the last one is XL."""
    return [round(_percentile(costs, p), 4) for p in (25, 50, 75)] if costs else []


def size_class(cost: float, bounds: List[float]) -> str:
    if not bounds:
        return ""
    for name, bound in zip(CLASSES, bounds):
        if cost <= bound:
            return name
    return CLASSES[-1]


def _scale(task: Dict[str, Any], comparable: List[Dict[str, Any]]) -> float:
    ratios = []
    for key in ("checkboxes", "chars"):
        median = _median([float(c["features"][key]) for c in comparable])
        if task[key] > 0 and median > 0:
            ratios.append(task[key] / median)
    if not ratios:
        return 1.0
    value = math.exp(sum(math.log(r) for r in ratios) / len(ratios))
    return min(SCALE_LIMITS[1], max(SCALE_LIMITS[0], value))


def history(finished: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], str]:
    """(the finished tasks forecasts compare with, "orchestrator" | "all"): only ORCHESTRATOR-run ones once there
    are MIN_ORCHESTRATED of them."""
    same = [f for f in finished if f.get("orchestrator") == ORCHESTRATOR]
    return (same, ORCHESTRATOR) if len(same) >= MIN_ORCHESTRATED else (finished, "all")


def forecast(task: Dict[str, Any], finished: List[Dict[str, Any]], spent: float = 0.0) -> Optional[Dict[str, Any]]:
    """Expected weighted cost of a task from `finished` = [{id, cost, features, orchestrator}]; None without
    finished tasks.

    `{low, mid, high, scale, basis: [{id, cost}], group, history, low_confidence, spent}` - low/mid/high already
    minus `spent` (floored at 0)."""
    finished, pool = history(finished)
    if not finished:
        return None
    comparable = [f for f in finished if f["features"]["model"] == task["model"] and f["features"]["group"] == task["group"]]
    low_confidence = len(comparable) < MIN_COMPARABLE
    if low_confidence:
        comparable = finished
    costs = [float(c["cost"]) for c in comparable]
    scale = _scale(task, comparable)
    left = lambda value: round(max(0.0, value * scale - spent), 4)  # noqa: E731
    return {
        "low": left(_percentile(costs, 25)), "mid": left(_median(costs)), "high": left(_percentile(costs, 75)),
        "scale": round(scale, 3), "group": "%s · %s" % (task["model"], task["group"]), "history": pool,
        "basis": [{"id": c["id"], "cost": round(float(c["cost"]), 2)} for c in sorted(comparable, key=lambda c: c["id"])],
        "low_confidence": low_confidence, "spent": round(spent, 4),
    }  # fmt: skip


def percent(cost: float, ratio: Optional[float]) -> Optional[float]:
    return None if ratio is None else round(cost * ratio, 1)


def usage_rows(rows: List[Dict[str, Any]], texts: Dict[str, str], costs: Dict[str, Dict[str, Any]],
               ratios: Dict[str, Optional[float]], limits: Dict[str, Dict[str, float]]) -> Dict[str, Dict[str, Any]]:  # fmt: skip
    """Task ID → the Usage column's data: `actual` for finished tasks with a measured cost, `forecast` for open ones.

    Every entry: kind, cost / low / mid / high (weighted), class (S…XL), pct ({window: [low, high]} or {window: value}
    when calibrated), and for forecasts basis, group, low_confidence, spent, and `wont_fit` (the reset time) when the
    upper estimate exceeds what is left of the live 5-hour window."""
    finished = [{"id": r["id"], "cost": costs[r["id"]]["cost"], "features": features(r, texts.get(r["id"], "")),
                 "orchestrator": costs[r["id"]].get("orchestrator", "")}
                for r in rows if r["status"] in FINISHED and r["id"] in costs and costs[r["id"]].get("cost", 0) > 0]  # fmt: skip
    bounds = size_classes([f["cost"] for f in finished])
    out: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        cost = costs.get(row["id"])
        if row["status"] in FINISHED and cost and cost.get("cost", 0) > 0:
            value = float(cost["cost"])
            out[row["id"]] = {"kind": "actual", "cost": round(value, 4), "class": size_class(value, bounds),
                              "sessions": cost.get("sessions"), "active_hours": cost.get("active_hours"),
                              "orchestrator": cost.get("orchestrator", ""),
                              "pct": {w: percent(value, r) for w, r in ratios.items() if r is not None}}  # fmt: skip
            continue
        if row["status"] not in FORECAST:
            continue
        spent = float(cost["cost"]) if cost and row["status"] == "in progress" else 0.0
        result = forecast(features(row, texts.get(row["id"], "")), [f for f in finished if f["id"] != row["id"]], spent)
        if result is None:
            continue
        result.update(kind="forecast", cost=result["mid"], **{"class": size_class(result["mid"] + spent, bounds)})
        result["pct"] = {w: [percent(result["low"], r), percent(result["high"], r)] for w, r in ratios.items() if r is not None}
        five = limits.get("five_hour")
        if five and "five_hour" in result["pct"] and result["pct"]["five_hour"][1] > 100.0 - five["utilization"] * 100.0:
            result["wont_fit"] = five["resets_at"]
        out[row["id"]] = result
    return out
