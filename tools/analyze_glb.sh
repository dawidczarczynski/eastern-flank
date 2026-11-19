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
#        tools/analyze_glb.sh --all [--force] [--no-measure] [--windows | --linux]   (TASK-183)
#   --all  analyse every unit that has a reference.glb and no fresh measurements.json (a stamp
#          <unit folder>/reference.glb.sha256 holds the GLB hash of the last successful run; without
#          a stamp, a measurements.json newer than the GLB counts as fresh; --force redoes all);
#          prints a table of the warnings per unit. Exit 1 when any unit failed.
# Exit codes as tools/render_unit.sh (1 also: no mesh in the GLB, size deviates from the catalog).
here="$(cd "$(dirname "$0")" && pwd)"
if [[ "${1:-}" != "--all" ]]; then
	exec "$here/render_unit.sh" --glb "$@"
fi
shift
units_dir="$here/../docs/design/units/units"
force=0
extra=()
for arg in "$@"; do
	if [[ "$arg" == "--force" ]]; then force=1; fi
	extra+=("$arg")
done
rows=()
failed=0
for glb in "$units_dir"/*/reference.glb; do
	[[ -f "$glb" ]] || continue
	dir="$(dirname "$glb")"
	id="$(basename "$dir")"
	hash="$(sha256sum "$glb" | cut -d' ' -f1)"
	stamp="$dir/reference.glb.sha256"
	fresh=0
	if [[ -f "$dir/measurements.json" && -f "$dir/normalisation.json" ]]; then
		if [[ -f "$stamp" ]]; then
			[[ "$(cat "$stamp")" == "$hash" ]] && fresh=1
		elif [[ "$dir/measurements.json" -nt "$glb" ]]; then
			fresh=1
		fi
	fi
	if [[ $fresh -eq 1 && $force -eq 0 ]]; then
		echo "== $id: up to date, skipped"
		rows+=("$id|skipped|")
		continue
	fi
	echo "== $id: analysing"
	"$here/render_unit.sh" --glb "$id" "${extra[@]}" >"$dir/.analyze.log" 2>&1
	code=$?
	# (same rule as tools/unit_catalog/jobs.py) the Windows Godot build exits 5 on leaked-resource noise after a good render: judge by the output
	if [[ $code -ne 1 && $code -ne 2 && $code -ne 124 && $code -ne 127 ]] && grep -q "^Render saved:" "$dir/.analyze.log"; then
		# a --no-measure run leaves measurements.json missing: no stamp, so the next --all completes it
		[[ -f "$dir/measurements.json" ]] && echo "$hash" >"$stamp"
		rows+=("$id|ok|$(python3 -I - "$dir" <<'PY'
import json, os, sys
d = sys.argv[1]
w = []
for name, key in (("normalisation.json", "warnings"), ("measurements.json", "warnings")):
    try:
        w += json.load(open(os.path.join(d, name))).get(key, [])
    except (OSError, ValueError):
        pass
print(" ; ".join(str(x) for x in w))
PY
)")
	else
		failed=1
		rows+=("$id|FAILED|exit $code: $(grep -E "^(ERROR|Real:)" "$dir/.analyze.log" | head -n 1)")
	fi
	rm -f "$dir/.analyze.log"
done
echo
printf '%-22s %-8s %s\n' UNIT RESULT WARNINGS
for row in "${rows[@]}"; do
	IFS='|' read -r id result warn <<<"$row"
	printf '%-22s %-8s %s\n' "$id" "$result" "${warn:--}"
done
exit $failed
