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

output=$("$GODOT" --headless --path . --script res://tests/run_tests.gd -- "$@" 2>&1)
status=$?
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
