#!/usr/bin/env bash
# Compares the silhouette of a unit's game model with its reference GLB (TASK-181) in three
# orthographic views (side, front, top): IoU, area difference, a diff image per view in
# .screenshots/units/<id>_diff_<view>.png (grey = both, red = only in the model, blue = only in
# the GLB) and the largest mismatch regions in metres. No rendering: both meshes are rasterised
# (tools/silhouette.gd), so it runs headless in a few seconds.
# Usage: tools/compare_silhouette.sh <unit_id> [--min-iou=0.90] [--pixel=0.02]
#                                    [--front=+x|-x|+z|-z] [--faction=<id>]
#   --min-iou  every view must reach it, else exit 1 (default 0.90)
#   --pixel    mask resolution in metres (default 0.02)
#   --front    the GLB axis pointing to the front (default: as tools/analyze_glb.sh recorded it in
#              normalisation.json, else the narrower end of the longer axis)
# Needs docs/design/units/units/<id>/reference.glb (not in git) and the model file
# src/presentation/models/<id>.gd. Both meshes are centred in x / z over their bounding boxes and
# stand on the ground, so a length difference shows at both ends.
# The last stdout lines: "IoU side=0.93 front=0.90 top=0.91 (min 0.90: ok)" and up to 3 lines
# "Mismatch: <view> extra|missing <m2>: <axis range> ..., model +0.12 m high" (extra = only in the
# model, missing = only in the GLB).
# Exit codes: 0 all IoU >= min, 1 below it / failure, 2 invalid arguments, 127 Godot not found.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/godot" ]]; then
	GODOT="$HOME/.local/bin/godot"
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Could not find '$GODOT'. Install it: tools/install_godot.sh or set GODOT=/path/to/godot" >&2
	exit 127
fi

# .gdignore keeps Godot from importing the PNGs; the import refreshes the class cache.
mkdir -p .screenshots/units
touch .screenshots/.gdignore
timeout 120 "$GODOT" --headless --path . --import >/dev/null 2>&1

errors="$(mktemp)"
trap 'rm -f "$errors"' EXIT
timeout 300 "$GODOT" --headless --path . --script res://tools/compare_silhouette.gd -- "$@" 2>"$errors"
status=$?
cat "$errors" >&2
if [[ $status -eq 0 ]] && grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
exit $status
