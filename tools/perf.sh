#!/usr/bin/env bash
# Frame cost of the battle scene on the GPU: frame time, draw calls, triangles and a breakdown of
# what each part of the picture costs (grass, trees, shadows, SSAO, MSAA, ...; tools/perf_profile.gd).
# Run it before and after adding a visual detail; the budget is 16.6 ms (60 FPS) on the target GPU.
# Usage: tools/perf.sh [--no-breakdown | --only=trees,shadows] [--resolution=1920x1080] [--scenario=<name>]
#   --only  run only the breakdown rows whose name contains one of these words
#   Camera: SCREENSHOT_CAMERA / SCREENSHOT_FOCUS as for tools/screenshot.sh (default: the overview).
#   Other tools/screenshot.sh options and variables pass through (--quality=low, --linux, ...).
set -uo pipefail
cd "$(dirname "$0")/.."
resolution="${SCREENSHOT_RESOLUTION:-1920x1080}"
profile=1
args=()
for arg in "$@"; do
	case "$arg" in
	--no-breakdown) profile="" ;;
	--only=*) profile="${arg#--only=}" ;;
	--resolution=*) resolution="${arg#--resolution=}" ;;
	--scenario=*) export SCREENSHOT_SCENARIO="${arg#--scenario=}" ;;
	*) args+=("$arg") ;;
	esac
done
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
SCREENSHOT_RESOLUTION="$resolution" SCREENSHOT_PROFILE="$profile" \
	SCREENSHOT_MEASURE_FRAMES="${SCREENSHOT_MEASURE_FRAMES:-200}" \
	SCREENSHOT_TIME_LIMIT="${SCREENSHOT_TIME_LIMIT:-600}" \
	tools/screenshot.sh .screenshots/perf.png --frames=120 "${args[@]}" >"$log" 2>&1
status=$?
# The window may be smaller than asked for (desktop size), which fails only the PNG size check.
if ! grep -E "Using Device|Graphics quality|Frame time|Render:|^  (baseline|without) |Frame cost|SCRIPT ERROR|screenshot is" "$log"; then
	cat "$log"
	exit "$status"
fi
grep -q "Frame time" "$log"
