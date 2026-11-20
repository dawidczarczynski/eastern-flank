#!/usr/bin/env bash
# Large-map benchmark (TASK-072a): the Suwalki battle map tiled to 1x / 4x / 16x its area, built in
# a bare scene (tools/bench_large_map.gd); prints build time, memory, instances, triangles and draw
# calls per scale, and the frame time per camera distance plus a 10 s pan sweep.
# Usage: tools/bench_large_map.sh [--scale=1|4|16 | --all] [--quality=low|high] [--windows | --linux]
#   --all      1x, 4x and 16x one after the other (default: --scale=1)
#   --quality  force the graphics quality (default: auto-detected: HIGH with --windows, LOW with --linux)
#   --windows / --linux  Godot build, as for tools/screenshot.sh (default under WSL: Windows GPU build)
#   BENCH_TIME_LIMIT=<s>  limit per scale (default 900)
# Each scale runs in its own Godot process (memory is not shared). A scale that crashes or runs out
# of time prints "FAILED <scale> (<reason>)" with the last log lines; the other scales still run.
set -uo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
# shellcheck source=tools/windows_godot.sh
source tools/windows_godot.sh

scales=(1)
quality=()
platform=""
for arg in "$@"; do
	case "$arg" in
	--all) scales=(1 4 16) ;;
	--scale=1 | --scale=4 | --scale=16) scales=("${arg#--scale=}") ;;
	--quality=low | --quality=high) quality=("$arg") ;;
	--windows) platform="windows" ;;
	--linux) platform="linux" ;;
	*)
		echo "Usage: tools/bench_large_map.sh [--scale=1|4|16 | --all] [--quality=low|high] [--windows | --linux]" >&2
		exit 2
		;;
	esac
done

godot_win="$(pick_windows_godot "$platform")" || exit 127
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/godot" ]]; then
	GODOT="$HOME/.local/bin/godot"
fi
if [[ -z "$godot_win" ]] && ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Could not find '$GODOT'. Install it: tools/install_godot.sh or set GODOT=/path/to/godot" >&2
	exit 127
fi
if [[ -z "$godot_win" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	echo "ERROR: no graphical environment (neither DISPLAY nor WAYLAND_DISPLAY is set)." >&2
	exit 2
fi

limit="${BENCH_TIME_LIMIT:-900}"
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1

output="$(mktemp)"
errors="$(mktemp)"
trap 'rm -f "$output" "$errors"' EXIT
build_rows=()
frame_rows=()
failed=0
for scale in "${scales[@]}"; do
	echo "== scale ${scale}x ==" >&2
	if [[ -n "$godot_win" ]]; then
		run_windows_godot "$godot_win" "$limit" "$output" "$errors" "$project_dir" \
			--script res://tools/bench_large_map.gd -- "--scale=$scale" "${quality[@]}"
	else
		timeout "$limit" "$GODOT" --path . --script res://tools/bench_large_map.gd -- \
			"--scale=$scale" "${quality[@]}" >"$output" 2>"$errors"
	fi
	status=$?
	grep "^Graphics quality" "$output" | head -1
	while IFS= read -r line; do build_rows+=("$line"); done < <(grep "^BUILD " "$output")
	while IFS= read -r line; do frame_rows+=("$line"); done < <(grep "^FRAME " "$output")
	if [[ $status -ne 0 ]] || grep -qE "SCRIPT ERROR|Parse Error" "$errors"; then
		failed=1
		echo "FAILED ${scale}x (exit $status$([[ $status -eq 124 ]] && echo ", time limit"))"
		tail -8 "$output"
		tail -8 "$errors"
	fi
done

echo
printf '%-6s %-7s %-9s %-9s %-10s %-9s %-11s %-9s %s\n' scale hexes build_s grass_s static_MB video_MB instances tris_k draws
for row in "${build_rows[@]}"; do
	read -r _ s h b g m v i t d <<<"$row"
	printf '%-6s %-7s %-9s %-9s %-10s %-9s %-11s %-9s %s\n' "${s}x" "$h" "$b" "$g" "$m" "$v" "$i" "$t" "$d"
done
echo
printf '%-6s %-8s %-9s %-9s %-7s %s\n' scale camera avg_ms max_ms frames ">33ms"
for row in "${frame_rows[@]}"; do
	read -r _ s c a m n sl <<<"$row"
	printf '%-6s %-8s %-9s %-9s %-7s %s\n' "${s}x" "$c" "$a" "$m" "$n" "$sl"
done
exit $failed
