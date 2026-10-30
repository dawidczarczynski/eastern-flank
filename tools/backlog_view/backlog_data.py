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

TASKS_DIR = backlog.TASKS_DIR
TASK_FILE = re.compile(r"^TASK-[\w.-]+\.md$")
META_LINE = re.compile(r"^- \*\*([^*]+)\*\*: (.+)$", re.MULTILINE)
MODEL_NAME = re.compile(r"^`?(opus|sonnet|haiku)\b", re.IGNORECASE)
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


def _split_table(text: str) -> tuple:
    """(text before the table, text after it) – the backlog's intro and notes."""
    lines = text.splitlines()
    table = [i for i, line in enumerate(lines) if line.startswith("|")]
    if not table:
        return text, ""
    return "\n".join(lines[: table[0]]).strip(), "\n".join(lines[table[-1] + 1 :]).strip()


def load(tasks_dir: Optional[Path] = None) -> Dict[str, Any]:
    tasks_dir = tasks_dir or TASKS_DIR
    text = (tasks_dir / "BACKLOG.md").read_text(encoding="utf-8")
    lines = text.splitlines()
    rows: List[Dict[str, Any]] = []
    for order, row in enumerate(backlog.parse_rows(text)):
        cells = [cell.strip() for cell in lines[row["line"]].strip().strip("|").split("|")]
        deps_cell = cells[3]
        hard = row["deps"]
        soft = [dep for dep in dict.fromkeys(backlog.TASK_ID.findall(deps_cell)) if dep not in hard and dep != row["id"]]
        meta: Dict[str, str] = {}
        if row["file"] and (tasks_dir / row["file"]).is_file():
            meta = task_meta((tasks_dir / row["file"]).read_text(encoding="utf-8"))
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
    return {"rows": rows, "intro": intro, "notes": notes, "statuses": STATUS_ORDER, "icons": backlog.STATUS_ICONS}


def version(tasks_dir: Optional[Path] = None) -> str:
    """Changes whenever BACKLOG.md or a task file is added, removed or modified."""
    tasks_dir = tasks_dir or TASKS_DIR
    stats = sorted((p.name, p.stat().st_mtime_ns, p.stat().st_size) for p in tasks_dir.glob("*.md"))
    return hashlib.sha1(repr(stats).encode()).hexdigest()[:12]


def read_task(name: str, tasks_dir: Optional[Path] = None) -> Optional[str]:
    """A task file's markdown, or None for anything that is not a task file in docs/tasks/."""
    tasks_dir = tasks_dir or TASKS_DIR
    if not TASK_FILE.match(name):
        return None
    path = tasks_dir / name
    return path.read_text(encoding="utf-8") if path.is_file() else None
