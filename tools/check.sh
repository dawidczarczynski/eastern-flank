#!/usr/bin/env bash
# Full verification before handing in a task: lint + tests. The agent MUST run this before finishing work.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== lint =="
tools/lint.sh
echo "== tests =="
tools/test.sh
echo "== backlog statuses =="
python3 tools/backlog.py
echo "== catalog tests =="
python3 -m unittest discover -s tools/unit_catalog -p 'test_*.py'
echo "== backlog viewer tests =="
python3 -m unittest discover -s tools/backlog_view -p 'test_*.py'
echo "== devtools hub tests =="
python3 -m unittest discover -s tools/devtools -p 'test_*.py'
echo "== task usage tests =="
python3 -m unittest discover -s tools -p 'test_task_cost.py'
python3 -m unittest discover -s tools -p 'test_usage_forecast.py'
echo "== map import tests =="
python3 -m unittest discover -s tools -p 'test_import_map.py'
echo "== OK =="
