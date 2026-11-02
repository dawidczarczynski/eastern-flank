#!/usr/bin/env bash
# Full verification before handing in a task: lint + tests. The agent MUST run this before finishing work.
# Prints the time of every step (the Godot tests are ~all of it; iterate with tools/test.sh <filter>).
set -euo pipefail
cd "$(dirname "$0")/.."

step() {
	local title="$1"
	shift
	local start=$SECONDS
	echo "== $title =="
	"$@"
	echo "   ($((SECONDS - start)) s)"
}

step "lint" tools/lint.sh
step "code map" python3 tools/codemap.py
step "tests" tools/test.sh
step "backlog statuses" python3 tools/backlog.py
step "catalog tests" python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'
step "backlog viewer tests" python3 -m unittest discover -s tools/backlog_view -p 'test_*.py'
step "devtools hub tests" python3 -m unittest discover -s tools/devtools -p 'test_*.py'
step "task cost tests" python3 -m unittest discover -s tools -p 'test_task_cost.py'
step "usage forecast tests" python3 -m unittest discover -s tools -p 'test_usage_forecast.py'
step "map import tests" python3 -m unittest discover -s tools -p 'test_import_map.py'
echo "== OK =="
