#!/usr/bin/env bash
# Compares AutoResolve with played AI-vs-AI battles (TASK-128). Usage: tools/calibrate_auto_resolve.sh [--seeds=50] [--max-turns=60] [--case=fortress] [--rules=ROUNDS:BREAK,...]
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

output=$("$GODOT" --headless --path . --script res://tools/calibrate_auto_resolve.gd -- "$@" 2>&1)
status=$?
# Drop Godot's version banner (and the blank line after it) so the output matches the documented format.
awk '/^Godot Engine v/ { skip = 1; next } skip && /^$/ { skip = 0; next } { skip = 0; print }' <<<"$output"

# A script runtime error in Godot doesn't abort the script – we catch it from the log.
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" <<<"$output"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
