#!/usr/bin/env python3
"""Keeps the `blocked` / `ready` statuses in docs/tasks/BACKLOG.md consistent with the dependencies.

A specified task is `blocked` while any of its hard dependencies is not `done`, and `ready` once all of
them are. Hard dependencies are the task IDs in the "Depends on" column before the first `soft`, `(`
or `;` (e.g. `**TASK-044**, TASK-042 (soft: TASK-050)` → TASK-044, TASK-042).

Every status cell in BACKLOG.md starts with a coloured icon (STATUS_ICONS); --fix adds or corrects it,
so a status can be written as plain text.

Usage: tools/backlog.py          – report inconsistencies, exit 1 if there are any (run by tools/check.sh)
       tools/backlog.py --fix    – rewrite the statuses in BACKLOG.md and the task files' Status lines
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TASKS_DIR = Path(__file__).resolve().parent.parent / "docs" / "tasks"
BACKLOG = TASKS_DIR / "BACKLOG.md"
TASK_ID = re.compile(r"TASK-\d+[a-z]?")
LINK = re.compile(r"\[(TASK-\d+[a-z]?)\]\(([^)]+)\)")
STATUS_LINE = re.compile(r"^(- \*\*Status\*\*: )(ready|blocked)\b", re.MULTILINE)
SWITCHABLE = ("ready", "blocked")
# Matched as a prefix of the status text, e.g. "done (superseded by …)" gets the `done` icon.
STATUS_ICONS = {
	"idea": "💡",
	"blocked": "🔴",
	"ready": "🟢",
	"in progress": "🟡",
	"to playtest": "🟣",
	"done": "🔵",
	"merged": "⚪",
}


def strip_icon(cell: str) -> str:
	for icon in STATUS_ICONS.values():
		if cell.startswith(icon):
			return cell[len(icon) :].strip()
	return cell


def with_icon(status: str) -> str:
	for name, icon in STATUS_ICONS.items():
		if status.startswith(name):
			return f"{icon} {status}"
	return status


def hard_dependencies(cell: str) -> list[str]:
	head = re.split(r"soft|\(|;", cell, maxsplit=1)[0]
	return TASK_ID.findall(head)


def parse_rows(text: str) -> list[dict]:
	rows = []
	for index, line in enumerate(text.splitlines()):
		cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
		if len(cells) != 4 or not TASK_ID.match(cells[0].lstrip("[")):
			continue
		link = LINK.match(cells[0])
		rows.append(
			{
				"line": index,
				"id": link.group(1) if link else cells[0],
				"file": link.group(2) if link else None,
				"cell": cells[2],
				"status": strip_icon(cells[2]),
				"deps": hard_dependencies(cells[3]),
			}
		)
	return rows


def expected_statuses(rows: list[dict]) -> tuple[dict[str, str], list[str]]:
	done = {row["id"] for row in rows if row["status"].startswith("done")}
	known = {row["id"] for row in rows}
	expected: dict[str, str] = {}
	errors: list[str] = []
	for row in rows:
		status = row["status"].split(" ")[0]
		if status not in SWITCHABLE:
			continue
		unknown = [dep for dep in row["deps"] if dep not in known]
		if unknown:
			errors.append(f"{row['id']}: unknown dependencies {', '.join(unknown)}")
		pending = [dep for dep in row["deps"] if dep not in done]
		expected[row["id"]] = "blocked" if pending else "ready"
	return expected, errors


def main() -> int:
	fix = "--fix" in sys.argv[1:]
	text = BACKLOG.read_text(encoding="utf-8")
	rows = parse_rows(text)
	expected, errors = expected_statuses(rows)
	lines = text.splitlines(keepends=True)
	problems: list[str] = []
	for row in rows:
		want = expected.get(row["id"])
		status = row["status"]
		if want is not None and status.split(" ")[0] != want:
			problems.append(f"{row['id']}: BACKLOG.md says '{status}', expected '{want}'")
			status = want + status[len(status.split(" ")[0]) :]
		cell = with_icon(status)
		if cell == status:
			errors.append(f"{row['id']}: unknown status '{status}' (known: {', '.join(STATUS_ICONS)})")
		elif cell != row["cell"]:
			if status == row["status"]:
				problems.append(f"{row['id']}: BACKLOG.md status '{row['cell']}' needs the icon '{cell}'")
			lines[row["line"]] = lines[row["line"]].replace(f"| {row['cell']} |", f"| {cell} |", 1)
		if want is not None and row["file"]:
			path = TASKS_DIR / row["file"]
			task_text = path.read_text(encoding="utf-8")
			match = STATUS_LINE.search(task_text)
			if match and match.group(2) != want:
				problems.append(f"{row['id']}: {row['file']} says '{match.group(2)}', expected '{want}'")
				if fix:
					path.write_text(STATUS_LINE.sub(rf"\g<1>{want}", task_text, count=1), encoding="utf-8")
	for error in errors:
		print(f"ERROR {error}", file=sys.stderr)
	if fix and problems:
		BACKLOG.write_text("".join(lines), encoding="utf-8")
		for problem in problems:
			print(f"fixed {problem}")
		return 1 if errors else 0
	for problem in problems:
		print(f"ERROR {problem} (run tools/backlog.py --fix)", file=sys.stderr)
	return 1 if problems or errors else 0


if __name__ == "__main__":
	sys.exit(main())
