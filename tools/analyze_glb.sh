#!/usr/bin/env bash
# Normalises the reference GLB of a unit (docs/design/units/units/<id>/reference.glb, a Meshy
# model used instead of photos) to the catalog dimensions and renders it like render_unit.sh:
# docs/design/units/units/<id>/reference_views/glb_{side,front,top,three_quarter}.png + glb_sheet.png,
# normalisation.json (applied yaw, scale, size, warnings) and measurements.json (section profiles and
# model constants DECK_H, ROOF_H, TURRET_X, ... with confidences and warnings; TASK-180) next to the
# GLB. The GLB itself is not in git.
# Usage: tools/analyze_glb.sh <unit_id> [--front=+x|-x|+z|-z] [--force] [--no-measure] [--views=...]
#                             [--out=sheet.png] [--windows | --linux]
#   --front  the GLB axis that points to the front (default: the narrower end of the longer axis)
#   --force  render even if the size deviates > 25 % from the catalog
#   --no-measure  skip measurements.json (~20 s for a 2 M triangle GLB)
# Exit codes as tools/render_unit.sh (1 also: no mesh in the GLB, size deviates from the catalog).
exec "$(dirname "$0")/render_unit.sh" --glb "$@"
