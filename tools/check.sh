#!/usr/bin/env bash
# Full verification before handing in a task: lint + tests. The agent MUST run this before finishing work.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== lint =="
tools/lint.sh
echo "== tests =="
tools/test.sh
echo "== OK =="
