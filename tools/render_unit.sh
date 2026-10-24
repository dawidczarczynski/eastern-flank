#!/usr/bin/env bash
# Renders one unit model alone (model-space grid, battle sun, faction camo) from fixed angles and
# writes per-view PNGs and a sheet: 2 x 2 views (side, front, top orthographic at the same scale;
# three_quarter perspective) with the reference image next to them – lets the unit-modeler agent
# compare a model with the real unit.
# Usage: tools/render_unit.sh <unit_id> [--faction=<id>] [--views=side,front,top,three_quarter]
#                             [--reference=path] [--out=sheet.png] [--pose=rest|fire]
#                             [--windows | --linux]
#   unit_id      model file src/presentation/models/<unit_id>.gd
#   --faction    camo to render (default: first of the catalog entry's operators that is a faction in
#                data/factions/, else poland)
#   --views      comma separated, any of side,front,top,three_quarter (default: all four)
#   --reference  image shown next to the side view (default: the first existing side, else drawing,
#                image of docs/design/units/units/<unit_id>/unit.json; none if there isn't one)
#   --out        sheet path (default .screenshots/units/<unit_id>_<faction>_sheet.png); the view PNGs
#                are written next to it as <name without _sheet>_<view>.png. Relative paths are
#                resolved against the current directory; keep them under .screenshots/ or outside the
#                project – elsewhere Godot would import the PNG.
#   --pose       rest (default: as built) or fire (a launcher raised to its max_elevation_deg at
#                traverse 0 – checks the actuators at full extension; the stats AABB is that pose's)
#   --windows    render with the Windows Godot console build (GPU, D3D12, Forward+) – the default under
#                WSL when it is found (tools/windows_godot.sh; GODOT_WIN overrides the path)
#   --linux      render with the Linux Godot (under WSLg: software OpenGL, no Forward+ effects)
# The last stdout lines are "Render saved: <sheet>", "Stats: aabb_m=<L>x<W>x<H> triangles=<n>
# mesh_instances=<n> pivots=<names>" and, when the catalog entry has dimensions,
# "Real: <L>x<W>x<H> m, diff: <L%>/<W%>/<H%>".
# Exit codes: 0 saved, 1 blank image / script error / failure, 2 no display or invalid arguments
#             (unknown unit without a model file, unknown faction, view or pose, missing id),
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

# --windows / --linux pick the Godot build; --reference= and --out= values are made absolute
# (relative to the caller); everything else is validated by tools/render_unit_options.gd.
platform=""
args=()
for arg in "$@"; do
	case "$arg" in
	--windows) platform="windows" ;;
	--linux) platform="linux" ;;
	--reference=* | --out=*)
		name="${arg%%=*}"
		value="${arg#*=}"
		if [[ -n "$value" && "$value" != /* ]]; then
			value="$caller_dir/$value"
		fi
		args+=("$name=$value")
		;;
	*)
		args+=("$arg")
		;;
	esac
done

godot_win="$(pick_windows_godot "$platform")" || exit 127
if [[ -z "$godot_win" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	echo "ERROR: no graphical environment (neither DISPLAY nor WAYLAND_DISPLAY is set) – renders need a window." >&2
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
mkdir -p .screenshots/units
touch .screenshots/.gdignore

# Importing refreshes the class cache (class_name) – without it new classes are not visible in
# --script mode. The Linux build does it for both (the cache is shared through the project folder).
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

# Godot prints its own log lines before the result, so the last stdout lines are the script's result.
# stderr is collected so that script errors fail the run (like tools/screenshot.sh).
if [[ -n "$godot_win" ]]; then
	win_args=()
	for arg in "${args[@]}"; do
		case "$arg" in
		--reference=/* | --out=/*) win_args+=("${arg%%=*}=$(wslpath -w "${arg#*=}")") ;;
		*) win_args+=("$arg") ;;
		esac
	done
	run_windows_godot "$godot_win" "$remaining" "$output" "$errors" "$project_dir" \
		--resolution 1280x720 --script res://tools/render_unit.gd -- "${win_args[@]}"
	status=$?
	print_with_wsl_paths "$output" "Render saved: "
else
	driver=()
	if [[ -n "${GODOT_RENDERING_DRIVER:-}" ]]; then
		driver=(--rendering-driver "$GODOT_RENDERING_DRIVER")
	fi
	timeout "$remaining" "$GODOT" --path . --resolution 1280x720 "${driver[@]}" \
		--script res://tools/render_unit.gd -- "${args[@]}" 2>"$errors"
	status=$?
fi
cat "$errors" >&2
if [[ $status -eq 0 ]] && grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
