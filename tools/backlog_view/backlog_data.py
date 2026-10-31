"""Backlog data for the backlog viewer: the BACKLOG.md table as JSON rows plus task file metadata.

The table is parsed by tools/backlog.py (one parser for the checker and the viewer).
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import backlog  # noqa: E402
import task_cost  # noqa: E402
import usage_forecast  # noqa: E402

TASKS_DIR = backlog.TASKS_DIR
COSTS_FILE = "task_costs.json"  # in the tasks dir, written by tools/task_cost.py
CALIBRATION_FILE = "usage_calibration.jsonl"  # in the tasks dir, appended by the devtools chat
LIMITS_FILE = backlog.TASKS_DIR.parent.parent / ".devtools" / "limits.json"  # the live windows, written by devtools
TASK_FILE = re.compile(r"^TASK-[\w.-]+\.md$")
META_LINE = re.compile(r"^- \*\*([^*]+)\*\*: (.+)$", re.MULTILINE)
MODEL_NAME = re.compile(r"^`?(opus|sonnet|haiku)\b", re.IGNORECASE)
# A notes paragraph that opens a topic: `HUD v3 (TASK-076 … TASK-082, handoff …): …`.
TOPIC_LINE = re.compile(r"^([A-Z][^(|\n]*?) \([^)]*?(TASK-\d+[a-z]?) … (TASK-\d+[a-z]?)")
# Tasks before the first topic's range (the skeleton and the first rules).
FIRST_TOPIC = "Foundation"
OTHER_TOPIC = "Other"
# Workflow order, used to sort by status.
STATUS_ORDER = ["in progress", "to playtest", "ready", "blocked", "idea", "done", "merged"]


def status_key(status: str) -> str:
    for name in STATUS_ORDER:
        if status.startswith(name):
            return name
    return "unknown"


def task_meta(text: str) -> Dict[str, str]:
    """The `- **Key**: value` lines of a task file header (Status, Layers, Depends on, Model …)."""
    header = text.split("\n## ", 1)[0]
    return {key.strip().lower(): value.strip() for key, value in META_LINE.findall(header)}


def model_name(text: str) -> str:
    """`opus (two large models …)` → `opus`; empty when the line names no model."""
    match = MODEL_NAME.match(text)
    return match.group(1).lower() if match else ""


def id_key(task_id: str) -> int:
    """TASK-039a → 3901: numeric order of task IDs, letter suffixes after the plain number."""
    match = re.match(r"TASK-(\d+)([a-z]?)", task_id)
    if not match:
        return 0
    return int(match.group(1)) * 100 + (ord(match.group(2)) - 96 if match.group(2) else 0)


def topic_sections(notes: str) -> List[Dict[str, Any]]:
    """The topics the notes below the table open: name, task ID range and the paragraphs' text."""
    sections: List[Dict[str, Any]] = []
    for line in notes.splitlines():
        match = TOPIC_LINE.match(line)
        if match:
            sections.append({"name": match.group(1).strip(), "first": match.group(2), "last": match.group(3), "text": ""})
        if sections:
            sections[-1]["text"] += line + "\n"
    return sections


def _mentions(text: str) -> List[int]:
    """ID keys a section's text names: `TASK-067` or the short form of the order lines (`030 → 062 → 067`)."""
    return [id_key("TASK-" + num) for num in re.findall(r"(?:TASK-|\b)(\d{3}[a-z]?)\b", text)]


def assign_topics(rows: List[Dict[str, Any]], sections: List[Dict[str, Any]], explicit: Dict[str, str]) -> Dict[str, str]:
    """Task ID → topic: a `- **Topic**:` line in the task file wins; else the section whose range holds the ID;
    else the section whose text names it most often; else the last section that starts before it.
    IDs below the first range belong to FIRST_TOPIC."""
    result: Dict[str, str] = {}
    first = min((id_key(s["first"]) for s in sections), default=None)
    mentions = [_mentions(s["text"]) for s in sections]
    for row in rows:
        key = id_key(row["id"])
        if row["id"] in explicit:
            result[row["id"]] = explicit[row["id"]]
            continue
        if first is None:
            result[row["id"]] = OTHER_TOPIC
            continue
        if key < first:
            result[row["id"]] = FIRST_TOPIC
            continue
        inside = [s for s in sections if id_key(s["first"]) <= key <= id_key(s["last"])]
        if inside:
            result[row["id"]] = inside[0]["name"]
            continue
        counts = [m.count(key) for m in mentions]
        if max(counts) > 0:
            result[row["id"]] = sections[counts.index(max(counts))]["name"]
            continue
        before = [s for s in sections if id_key(s["first"]) <= key]
        result[row["id"]] = max(before, key=lambda s: id_key(s["first"]))["name"]
    return result


def build_tree(rows: List[Dict[str, Any]], topic_of: Dict[str, str], topic_order: List[str]) -> List[Dict[str, Any]]:
    """The backlog as one dependency tree per topic.

    A task's links are its hard dependencies, or its soft ones when it has none. It hangs under the deepest
    link in its own topic (longest dependency chain, then the later row); its other links in the topic are
    `also`, links into other topics `external`. A task without a link in its topic is a root of the topic.
    """
    by_id = {row["id"]: row for row in rows}
    links = {row["id"]: [d for d in (row["hard"] or row["soft"]) if d in by_id and d != row["id"]] for row in rows}
    depth: Dict[str, int] = {}

    def depth_of(task_id: str, visiting: frozenset = frozenset()) -> int:
        if task_id in depth:
            return depth[task_id]
        parents = [d for d in links[task_id] if d not in visiting]
        value = 1 + max((depth_of(d, visiting | {task_id}) for d in parents), default=-1)
        depth[task_id] = value
        return value

    nodes: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        topic = topic_of[row["id"]]
        own = [d for d in links[row["id"]] if topic_of[d] == topic]
        parent = max(own, key=lambda d: (depth_of(d), by_id[d]["order"])) if own else None
        nodes[row["id"]] = {
            "id": row["id"],
            "parent": parent,
            "also": [d for d in own if d != parent],
            "external": [{"id": d, "topic": topic_of[d]} for d in links[row["id"]] if topic_of[d] != topic],
            "children": [],
        }
    # a parent chain that loops back (a dependency cycle) is cut at the task that closes it
    for row in rows:
        seen = {row["id"]}
        current = nodes[row["id"]]["parent"]
        while current is not None:
            if current in seen:
                nodes[row["id"]]["parent"] = None
                break
            seen.add(current)
            current = nodes[current]["parent"]
    topics: Dict[str, List[Dict[str, Any]]] = {name: [] for name in topic_order}
    for row in rows:
        node = nodes[row["id"]]
        if node["parent"]:
            nodes[node["parent"]]["children"].append(node)
        else:
            topics.setdefault(topic_of[row["id"]], []).append(node)
    for node in nodes.values():
        del node["parent"]
    return [{"name": name, "roots": roots} for name, roots in topics.items() if roots]


def _split_table(text: str) -> tuple:
    """(text before the table, text after it) – the backlog's intro and notes."""
    lines = text.splitlines()
    table = [i for i, line in enumerate(lines) if line.startswith("|")]
    if not table:
        return text, ""
    return "\n".join(lines[: table[0]]).strip(), "\n".join(lines[table[-1] + 1 :]).strip()


def usage(rows: List[Dict[str, Any]], texts: Dict[str, str], tasks_dir: Path, limits_file: Optional[Path]) -> Dict[str, Any]:
    """The Usage column (tools/usage_forecast.py): sets `row["usage"]`, returns what the page needs about it."""
    costs = task_cost.load(tasks_dir / COSTS_FILE)
    fits = usage_forecast.calibration(tasks_dir / CALIBRATION_FILE)
    ratios = {window: fit["percent_per_cost"] for window, fit in fits.items()}
    limits = usage_forecast.current_limits(limits_file) if limits_file else {}
    per_task = usage_forecast.usage_rows(rows, texts, costs, ratios, limits)
    for row in rows:
        row["usage"] = per_task.get(row["id"])
    costs_path = tasks_dir / COSTS_FILE
    return {"calibration": fits, "limits": limits, "costs_scanned": costs_path.stat().st_mtime if costs_path.is_file() else None,
            "min_samples": usage_forecast.MIN_SAMPLES}  # fmt: skip


def load(tasks_dir: Optional[Path] = None, limits_file: Optional[Path] = None) -> Dict[str, Any]:
    tasks_dir = tasks_dir or TASKS_DIR
    text = (tasks_dir / "BACKLOG.md").read_text(encoding="utf-8")
    lines = text.splitlines()
    rows: List[Dict[str, Any]] = []
    texts: Dict[str, str] = {}
    explicit_topics: Dict[str, str] = {}
    for order, row in enumerate(backlog.parse_rows(text)):
        cells = [cell.strip() for cell in lines[row["line"]].strip().strip("|").split("|")]
        deps_cell = cells[3]
        hard = row["deps"]
        soft = [dep for dep in dict.fromkeys(backlog.TASK_ID.findall(deps_cell)) if dep not in hard and dep != row["id"]]
        meta: Dict[str, str] = {}
        if row["file"] and (tasks_dir / row["file"]).is_file():
            texts[row["id"]] = (tasks_dir / row["file"]).read_text(encoding="utf-8")
            meta = task_meta(texts[row["id"]])
            if meta.get("topic"):
                explicit_topics[row["id"]] = meta["topic"]
        rows.append(
            {
                "order": order,
                "id": row["id"],
                "file": row["file"] if row["file"] and (tasks_dir / row["file"]).is_file() else None,
                "title": cells[1],
                "status": status_key(row["status"]),
                "status_text": row["status"],
                "depends": deps_cell,
                "hard": hard,
                "soft": soft,
                "layers": meta.get("layers", ""),
                "model": model_name(meta.get("model", "")),
                "model_note": meta.get("model", ""),
            }
        )
    dependents: Dict[str, List[str]] = {}
    for row in rows:
        for dep in row["hard"]:
            dependents.setdefault(dep, []).append(row["id"])
    for row in rows:
        row["dependents"] = dependents.get(row["id"], [])
    intro, notes = _split_table(text)
    sections = topic_sections(notes)
    topic_of = assign_topics(rows, sections, explicit_topics)
    for row in rows:
        row["topic"] = topic_of[row["id"]]
    topic_order = [FIRST_TOPIC] + [s["name"] for s in sections] + [OTHER_TOPIC]
    return {
        "rows": rows,
        "intro": intro,
        "notes": notes,
        "statuses": STATUS_ORDER,
        "icons": backlog.STATUS_ICONS,
        "tree": build_tree(rows, topic_of, topic_order),
        "usage": usage(rows, texts, tasks_dir, limits_file),
    }


def version(tasks_dir: Optional[Path] = None, limits_file: Optional[Path] = None) -> str:
    """Changes whenever BACKLOG.md, a task file, the task costs or the calibration is added, removed or modified,
    or the live limits change."""
    tasks_dir = tasks_dir or TASKS_DIR
    files = list(tasks_dir.glob("*.md")) + [p for p in (tasks_dir / COSTS_FILE, tasks_dir / CALIBRATION_FILE) if p.is_file()]
    stats = sorted((p.name, p.stat().st_mtime_ns, p.stat().st_size) for p in files)
    limits = usage_forecast.current_limits(limits_file) if limits_file else {}
    return hashlib.sha1(repr((stats, sorted(limits.items()))).encode()).hexdigest()[:12]


def read_task(name: str, tasks_dir: Optional[Path] = None) -> Optional[str]:
    """A task file's markdown, or None for anything that is not a task file in docs/tasks/."""
    tasks_dir = tasks_dir or TASKS_DIR
    if not TASK_FILE.match(name):
        return None
    path = tasks_dir / name
    return path.read_text(encoding="utf-8") if path.is_file() else None
