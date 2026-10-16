#!/usr/bin/env bash
# Runs the game (needs a graphical environment – in WSL2 it works through WSLg).
# Usage: tools/run.sh [--editor]
# The Godot path can be overridden with the GODOT variable.
set -euo pipefail
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

# Importing refreshes the class cache (class_name) – without it a fresh clone fails with "not declared in the current scope" errors.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if [[ "${1:-}" == "--editor" ]]; then
	exec "$GODOT" --path . --editor
fi
exec "$GODOT" --path .
