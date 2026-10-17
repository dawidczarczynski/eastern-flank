#!/usr/bin/env bash
# Renders the battle scene in a window, saves a PNG of the viewport and quits – lets agents "see" the game.
# Usage: tools/screenshot.sh [out.png] [--frames=N]
#   out.png   default .screenshots/battle.png (project root); a relative path is resolved against the current directory.
#             Keep custom paths under .screenshots/ or outside the project – elsewhere Godot would import the PNG.
#   --frames  rendered frames to wait before capturing (1-600, default 10)
# Exit codes: 0 saved, 1 blank image / script error / failure, 2 no display or invalid arguments,
#             124 timeout (60 s for the whole run), 127 Godot not found.
# The Godot path can be overridden with GODOT; GODOT_RENDERING_DRIVER (e.g. opengl3) is passed as --rendering-driver.
set -uo pipefail
SECONDS=0
TIME_LIMIT=60
caller_dir="$PWD"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	echo "ERROR: no graphical environment (neither DISPLAY nor WAYLAND_DISPLAY is set) – screenshots need a window." >&2
	exit 2
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

# Positional arguments are output paths: make them absolute (relative to the caller). Options and
# validation are handled by tools/screenshot_options.gd.
args=()
has_output=0
for arg in "$@"; do
	if [[ "$arg" == -* ]]; then
		args+=("$arg")
	else
		has_output=1
		if [[ "$arg" == /* ]]; then
			args+=("$arg")
		else
			args+=("$caller_dir/$arg")
		fi
	fi
done
if [[ $has_output -eq 0 ]]; then
	args+=("$project_dir/.screenshots/battle.png")
fi

# .gdignore keeps Godot from importing the PNGs (no *.import files).
mkdir -p .screenshots
touch .screenshots/.gdignore

# Importing refreshes the class cache (class_name) – without it new classes are not visible in --script mode.
timeout "$TIME_LIMIT" "$GODOT" --headless --path . --import >/dev/null 2>&1
if [[ $? -eq 124 ]]; then
	echo "ERROR: import timed out" >&2
	exit 124
fi

driver=()
if [[ -n "${GODOT_RENDERING_DRIVER:-}" ]]; then
	driver=(--rendering-driver "$GODOT_RENDERING_DRIVER")
fi

# Godot prints its own log lines before the result, so the last stdout line is the script's result.
# stderr is collected so that script errors in the scene fail the run (like tools/test.sh).
remaining=$((TIME_LIMIT - SECONDS))
((remaining < 1)) && remaining=1
errors="$(mktemp)"
trap 'rm -f "$errors"' EXIT
timeout "$remaining" "$GODOT" --path . --resolution 1280x720 "${driver[@]}" \
	--script res://tools/screenshot.gd -- "${args[@]}" 2>"$errors"
status=$?
cat "$errors" >&2
if [[ $status -eq 0 ]] && grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
