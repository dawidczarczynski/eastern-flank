#!/usr/bin/env bash
# Checks GDScript formatting and style (gdtoolkit: pip install "gdtoolkit==4.*").
# Usage: tools/lint.sh [--fix]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v gdformat >/dev/null 2>&1; then
	echo "gdtoolkit not found – skipping lint. Install: pipx install 'gdtoolkit==4.*'" >&2
	exit 0
fi

if [[ "${1:-}" == "--fix" ]]; then
	gdformat src tests tools
	gdlint src tests tools
else
	# The two checks are independent; run them side by side.
	gdlint src tests tools &
	lint_pid=$!
	format_status=0
	gdformat --check src tests tools || format_status=$?
	wait "$lint_pid" || exit 1
	exit "$format_status"
fi
