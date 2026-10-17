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
else
	gdformat --check src tests tools
fi
gdlint src tests tools
