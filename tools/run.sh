#!/usr/bin/env bash
# Runs the game (needs a graphical environment – in WSL2 it works through WSLg).
# Usage: tools/run.sh [--editor] [--quality=low|high] [--scenario=<name>]
#   --quality  force the graphics quality (default: auto-detected; LOW on software rendering)
#   --scenario start the battle with that scenario (default_battle, objective_battle, command_points_battle)
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

user_args=()
editor=0
for arg in "$@"; do
	case "$arg" in
	--editor) editor=1 ;;
	--quality=* | --scenario=*) user_args+=("$arg") ;;
	esac
done
if [[ $editor -eq 1 ]]; then
	exec "$GODOT" --path . --editor
fi
if [[ ${#user_args[@]} -gt 0 ]]; then
	exec "$GODOT" --path . -- "${user_args[@]}"
fi
exec "$GODOT" --path .
