#!/usr/bin/env bash
# Water error report (TASK-223a): counts per rule and the first 20 positions of the rivers, lakes
# and bridges of a map (WaterValidator, ADR 0034). Headless.
# Usage: tools/water_report.sh [--map=<imported map id>] [--region=<col>:<row>]
#   --map     default suwalki (the battle map); a theatre id (suwalki_theatre) with --region
#   --region  the cut of that theatre's tactical layer around operational hex col:row, as the
#             devtools terrain viewer shows it (e.g. --map=suwalki_theatre --region=47:45)
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
"$GODOT" --headless --path . --import >/dev/null 2>&1
exec timeout 300 "$GODOT" --headless --path . --script res://tools/water_report.gd -- "$@"
