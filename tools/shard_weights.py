#!/usr/bin/env python3
"""Writes tests/shard_weights.json (ms per test file, balances the parallel shards of tools/test.sh) and
tests/slow_tests.txt (tests of 8 s or more, skipped by `tools/test.sh --fast`) from TEST_TIMES logs.

Usage: TEST_TIMES=1 tools/test.sh --verbose >/dev/null; tools/shard_weights.py   (reads .test.log by default)
       tools/shard_weights.py log1 log2 ...   (several logs, e.g. one per shard)
"""
import json
import re
import sys
from collections import defaultdict

paths = sys.argv[1:] or [".test.log"]
SLOW_MS = 8000  # tests at least this slow are skipped by `tools/test.sh --fast` / `tools/check.sh`
weights = defaultdict(int)
fast_weights = defaultdict(int)  # the same without the slow tests (balances `--fast` runs)
slow = []
for path in paths:
    for line in open(path, errors="replace"):
        m = re.match(r"\s+TIME (\d+) ((test_\w+\.gd):(\w+))", line)
        if m:
            ms = int(m.group(1))
            weights[m.group(3)] += ms
            if ms >= SLOW_MS and m.group(4) != "before_all":
                slow.append(m.group(2))
            else:
                fast_weights[m.group(3)] += ms
if not weights:
    sys.exit("no TIME lines found - run the tests with TEST_TIMES=1")
with open("tests/shard_weights.json", "w") as f:
    json.dump({k: [v, fast_weights[k]] for k, v in sorted(weights.items())}, f, indent=0)
    f.write("\n")
with open("tests/slow_tests.txt", "w") as f:
    f.write("".join(label + "\n" for label in sorted(set(slow))))
print(f"{len(set(slow))} slow tests (>= {SLOW_MS // 1000} s) -> tests/slow_tests.txt")
print(f"{len(weights)} files, {sum(weights.values()) / 1000:.0f} s total -> tests/shard_weights.json")
