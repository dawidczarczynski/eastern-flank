#!/usr/bin/env python3
"""Prints one section of a big doc instead of the whole file (keeps agents' context small).

Usage: tools/doc.py gdd|architecture|manual|<path>            – list the headings with line numbers
       tools/doc.py gdd|architecture|manual|<path> <heading>  – print the section(s) whose heading contains
                                                                <heading> (case-insensitive), with subsections
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
ALIASES = {"gdd": "GDD.md", "architecture": "ARCHITECTURE.md", "manual": "MANUAL.md", "vision": "VISION.md"}
HEADING = re.compile(r"^(#{1,6}) (.*)$")


def headings(lines: list[str]) -> list[tuple[int, int, str]]:
	found = []
	in_code = False
	for index, line in enumerate(lines):
		if line.startswith("```"):
			in_code = not in_code
		match = None if in_code else HEADING.match(line)
		if match:
			found.append((index, len(match.group(1)), match.group(2)))
	return found


def main() -> int:
	args = sys.argv[1:]
	if not args:
		print(__doc__)
		return 2
	path = DOCS / ALIASES[args[0]] if args[0] in ALIASES else Path(args[0])
	lines = path.read_text(encoding="utf-8").splitlines()
	found = headings(lines)
	if len(args) == 1:
		for index, level, title in found:
			print(f"{index + 1}\t{'  ' * (level - 1)}{title}")
		return 0
	query = " ".join(args[1:]).lower()
	hits = 0
	for position, (index, level, title) in enumerate(found):
		if query not in title.lower():
			continue
		end = len(lines)
		for next_index, next_level, _ in found[position + 1 :]:
			if next_level <= level:
				end = next_index
				break
		print(f"--- {path.name}:{index + 1}-{end} ---")
		print("\n".join(lines[index:end]))
		hits += 1
	if not hits:
		print(f"no heading contains '{query}' – list them with: tools/doc.py {args[0]}", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
