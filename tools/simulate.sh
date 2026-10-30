#!/usr/bin/env bash
# Plays N headless AI-vs-AI matches and prints win rates and average match length (TASK-012).
# Usage: tools/simulate.sh N [--seed=S] [--max-turns=T] [--factions=P0,P1]
#                          [--scenario=default_battle|objective_battle] [--verbose]
#   seeds S..S+N-1 (default S=1), harness turn limit T (default 50; a match still running then
#   counts as "Harness limit reached"), faction ids of player 0 and 1 (default poland,russia),
#   scenario (default default_battle); --verbose prints one line per match.
#   "Draws (rules)" are battles the rules ended without a winner (e.g. the battle's turn limit).
# The Godot path can be overridden with GODOT.
# Exit codes: 0 ok, 1 a match ended with "error" / script errors, 2 invalid arguments, 127 Godot not found.
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

output=$("$GODOT" --headless --path . --script res://tools/simulate.gd -- "$@" 2>&1)
status=$?
# Drop Godot's version banner (and the blank line after it) so the output matches the documented format.
awk '/^Godot Engine v/ { skip = 1; next } skip && /^$/ { skip = 0; next } { skip = 0; print }' <<<"$output"

# A script runtime error in Godot doesn't abort the script – we catch it from the log.
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" <<<"$output"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
