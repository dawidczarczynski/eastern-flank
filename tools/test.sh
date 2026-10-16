#!/usr/bin/env bash
# Runs the headless tests. Usage: tools/test.sh [filter]   (e.g. tools/test.sh test_hex)
# The Godot path can be overridden with the GODOT variable.
set -uo pipefail
cd "$(dirname "$0")/.."
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
echo "$output"

# A script runtime error in Godot doesn't abort the test – we catch it from the log.
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" <<<"$output"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
