#!/usr/bin/env bash
# Runs the headless tests. Usage: tools/test.sh [--verbose] [filter]   (e.g. tools/test.sh test_hex)
# Prints only failures, script errors and the summary; the full Godot log goes to .test.log
# (--verbose prints it all). The Godot path can be overridden with the GODOT variable.
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=.test.log
verbose=0
if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
	verbose=1
	shift
fi
GODOT="${GODOT:-godot}"

# tools/install_godot.sh installs to ~/.local/bin, which zsh does not have on PATH by default.
if ! command -v "$GODOT" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/godot" ]]; then
	GODOT="$HOME/.local/bin/godot"
fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Could not find '$GODOT'. Install it: tools/install_godot.sh or set GODOT=/path/to/godot" >&2
	exit 127
fi

# Importing refreshes the class cache (class_name) – without it new classes are not visible in --script mode.
"$GODOT" --headless --path . --import >/dev/null 2>&1

# Without a filter the test files are split over parallel Godot processes (TEST_SHARD=i/n, see
# tests/run_tests.gd); JOBS overrides the process count (default: min(cores, 4)).
jobs="${JOBS:-$(nproc 2>/dev/null || echo 1)}"
((jobs > 4)) && jobs=4
if (($# > 0)) || ((jobs < 2)); then
	jobs=1
fi

if ((jobs == 1)); then
	output=$("$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$@" 2>&1)
	status=$?
else
	shard_dir=$(mktemp -d)
	pids=()
	for ((i = 0; i < jobs; i++)); do
		TEST_SHARD="$i/$jobs" "$GODOT" --headless --path . --script res://tests/run_tests.gd >"$shard_dir/$i.log" 2>&1 &
		pids+=($!)
	done
	status=0
	for pid in "${pids[@]}"; do
		wait "$pid" || status=1
	done
	output=$(cat "$shard_dir"/*.log)
	# Merge the per-shard summaries into one line.
	total=$(grep -hoE "^[0-9]+ tests" "$shard_dir"/*.log | awk '{s+=$1} END{print s+0}')
	failed=$(grep -hoE "[0-9]+ failed" "$shard_dir"/*.log | awk '{s+=$1} END{print s+0}')
	output=$(grep -vE "^[0-9]+ tests, [0-9]+ failed" <<<"$output")
	output+=$'\n'"$total tests, $failed failed"
	rm -rf "$shard_dir"
fi
echo "$output" >"$LOG"

if ((verbose)); then
	echo "$output"
else
	# Failed tests with their messages, script errors with their location, and the summary line.
	grep -E -A2 "SCRIPT ERROR|Parse Error|Failed to load script" <<<"$output"
	grep -E "^  FAIL |^       - |^[0-9]+ tests, [0-9]+ failed" <<<"$output"
fi

# A script runtime error in Godot doesn't abort the test – we catch it from the log.
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" <<<"$output"; then
	echo "ERROR: the log contains script errors (see above; full log in $LOG)." >&2
	exit 1
fi
exit $status
