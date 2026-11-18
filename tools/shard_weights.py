#!/usr/bin/env python3
"""Writes tests/shard_weights.json (ms per test file) from TEST_TIMES logs, so tools/test.sh can balance its shards.

Usage: TEST_TIMES=1 tools/test.sh --verbose >/dev/null; tools/shard_weights.py   (reads .test.log by default)
       tools/shard_weights.py log1 log2 ...   (several logs, e.g. one per shard)
"""
import json
import re
import sys
from collections import defaultdict

paths = sys.argv[1:] or [".test.log"]
weights = defaultdict(int)
for path in paths:
    for line in open(path, errors="replace"):
        m = re.match(r"\s+TIME (\d+) (test_\w+\.gd):", line)
        if m:
            weights[m.group(2)] += int(m.group(1))
if not weights:
    sys.exit("no TIME lines found - run the tests with TEST_TIMES=1")
with open("tests/shard_weights.json", "w") as f:
    json.dump(dict(sorted(weights.items())), f, indent=0)
    f.write("\n")
print(f"{len(weights)} files, {sum(weights.values()) / 1000:.0f} s total -> tests/shard_weights.json")
