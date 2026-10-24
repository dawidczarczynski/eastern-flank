#!/usr/bin/env bash
# Renders the battle scene in a window, saves a PNG of the viewport and quits – lets agents "see" the game.
# Usage: tools/screenshot.sh [out.png] [--frames=N] [--windows | --linux] [--quality=low|high]
#   --quality force the graphics quality (default: auto-detected: HIGH with --windows, LOW with --linux); the run prints a "Graphics quality:" line
#   out.png   default .screenshots/battle.png (project root); a relative path is resolved against the current directory.
#             Keep custom paths under .screenshots/ or outside the project – elsewhere Godot would import the PNG.
#   --frames  rendered frames to wait before capturing (1-600, default 10)
#   --windows render with the Windows Godot console build (GPU, D3D12, Forward+ with SSAO) – the
#             default under WSL when it is found (tools/windows_godot.sh; GODOT_WIN overrides the path)
#   --linux   render with the Linux Godot (under WSLg: software OpenGL, Compatibility look, no SSAO)
#   SCREENSHOT_SCENE=menu|catalog renders the main menu / unit catalog instead of the battle (see the header of tools/screenshot.gd)
# Exit codes: 0 saved, 1 blank image / script error / failure, 2 no display or invalid arguments,
#             124 timeout (60 s for the whole run), 127 Godot not found.
# The Linux Godot path can be overridden with GODOT; GODOT_RENDERING_DRIVER (e.g. opengl3) is passed as --rendering-driver.
set -uo pipefail
SECONDS=0
TIME_LIMIT=60
caller_dir="$PWD"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# shellcheck source=tools/windows_godot.sh
source tools/windows_godot.sh

# --windows / --linux pick the Godot build; positional arguments are output paths: make them
# absolute (relative to the caller). Options and validation are handled by tools/screenshot_options.gd.
platform=""
args=()
has_output=0
for arg in "$@"; do
	case "$arg" in
	--windows) platform="windows" ;;
	--linux) platform="linux" ;;
	-*) args+=("$arg") ;;
	/*)
		has_output=1
		args+=("$arg")
		;;
	*)
		has_output=1
		args+=("$caller_dir/$arg")
		;;
	esac
done
if [[ $has_output -eq 0 ]]; then
	args+=("$project_dir/.screenshots/battle.png")
fi

godot_win="$(pick_windows_godot "$platform")" || exit 127
if [[ -z "$godot_win" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
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

# .gdignore keeps Godot from importing the PNGs (no *.import files).
mkdir -p .screenshots
touch .screenshots/.gdignore

# Importing refreshes the class cache (class_name) – without it new classes are not visible in --script mode.
timeout "$TIME_LIMIT" "$GODOT" --headless --path . --import >/dev/null 2>&1
if [[ $? -eq 124 ]]; then
	echo "ERROR: import timed out" >&2
	exit 124
fi

remaining=$((TIME_LIMIT - SECONDS))
((remaining < 1)) && remaining=1
errors="$(mktemp)"
output="$(mktemp)"
trap 'rm -f "$errors" "$output"' EXIT

# Godot prints its own log lines before the result, so the last stdout line is the script's result.
# stderr is collected so that script errors in the scene fail the run (like tools/test.sh).
if [[ -n "$godot_win" ]]; then
	win_args=()
	for arg in "${args[@]}"; do
		if [[ "$arg" == /* ]]; then
			win_args+=("$(wslpath -w "$arg")")
		else
			win_args+=("$arg")
		fi
	done
	GODOT_WIN_ENV="SCREENSHOT_SELECT_UNIT SCREENSHOT_HOVER_UNIT SCREENSHOT_CAMERA SCREENSHOT_PITCH_OFFSET SCREENSHOT_SCALE_PRESET SCREENSHOT_LOOK SCREENSHOT_MARKS SCREENSHOT_WRECK SCREENSHOT_FOCUS SCREENSHOT_MEASURE_FRAMES SCREENSHOT_NOTICE SCREENSHOT_SHOTS SCREENSHOT_SCENE SCREENSHOT_LOCALE SCREENSHOT_CATALOG" \
		run_windows_godot "$godot_win" "$remaining" "$output" "$errors" "$project_dir" \
		--resolution 1280x720 --script res://tools/screenshot.gd -- "${win_args[@]}"
	status=$?
	print_with_wsl_paths "$output" "Screenshot saved: "
else
	driver=()
	if [[ -n "${GODOT_RENDERING_DRIVER:-}" ]]; then
		driver=(--rendering-driver "$GODOT_RENDERING_DRIVER")
	fi
	timeout "$remaining" "$GODOT" --path . --resolution 1280x720 "${driver[@]}" \
		--script res://tools/screenshot.gd -- "${args[@]}" 2>"$errors"
	status=$?
fi
cat "$errors" >&2
if [[ $status -eq 0 ]] && grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
