#!/usr/bin/env bash
# Checks GDScript formatting and style (gdtoolkit: pip install "gdtoolkit==4.*").
# Usage: tools/lint.sh [--fix | --all]
# The check only looks at files changed since their last clean run (sha256 stamps in .lint-cache,
# ignored by git) and runs batches of them in parallel; --all ignores the cache. --fix formats everything.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v gdformat >/dev/null 2>&1; then
	echo "gdtoolkit not found – skipping lint. Install: pipx install 'gdtoolkit==4.*'" >&2
	exit 0
fi

if [[ "${1:-}" == "--fix" ]]; then
	gdformat src tests tools
	gdlint src tests tools
	exit 0
fi

CACHE=.lint-cache
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
# A new tool version, config or this script invalidates every stamp.
key=$( (gdlint --version; gdformat --version; cat .editorconfig tools/lint.sh 2>/dev/null) | sha256sum | cut -d' ' -f1)
[[ "${1:-}" == "--all" ]] && rm -f "$CACHE"
if [[ ! -f "$CACHE" || "$(head -n1 "$CACHE")" != "$key" ]]; then
	echo "$key" >"$CACHE"
fi

# "hash  path" for every .gd file, minus the ones already stamped clean.
current=$(find src tests tools -name '*.gd' -print0 | sort -z | xargs -0 sha256sum)
changed=$(comm -23 <(sort <<<"$current") <(tail -n +2 "$CACHE" | sort) | cut -d' ' -f3-)
if [[ -z "$changed" ]]; then
	echo "lint: all $(wc -l <<<"$current") files unchanged since the last clean run"
	exit 0
fi
echo "lint: checking $(wc -l <<<"$changed") of $(wc -l <<<"$current") files"

stamps=$(mktemp -d)
export stamps
check_batch() {
	local out
	if out=$(gdformat --check "$@" 2>&1 && gdlint "$@" 2>&1); then
		sha256sum "$@" >"$stamps/$$.$RANDOM"
	else
		echo "$out"
		return 1
	fi
}
export -f check_batch
status=0
tr '\n' '\0' <<<"$changed" | xargs -0 -n 12 -P "$JOBS" bash -c 'check_batch "$@"' _ || status=1

# Keep the stamps of files that are still unchanged, add the newly clean ones.
{
	echo "$key"
	{
		tail -n +2 "$CACHE"
		cat "$stamps"/* 2>/dev/null || true
	} | sort -u | grep -F -x -f <(sort <<<"$current") || true
} >"$CACHE.new"
mv "$CACHE.new" "$CACHE"
rm -rf "$stamps"
exit "$status"
