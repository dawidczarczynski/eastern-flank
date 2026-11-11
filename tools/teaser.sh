#!/usr/bin/env bash
# Records the Homar-K salvo teaser video (one-off promo tool; what it shows and how: the header of
# tools/teaser.gd): the Homar-K fires a salvo at the T-72B3 in the default battle and destroys it,
# filmed by a scripted cinematic camera, then the game logo. Godot renders it in Movie Maker mode at
# a fixed frame rate, so the video is smooth however slow the render is (1080p60: ~1000 frames,
# ~2 min on a Radeon RX 580). Under WSL it renders with the Windows Godot console build (GPU,
# Forward+, HIGH quality – what the human sees) when found, like tools/screenshot.sh.
# Usage: tools/teaser.sh [out.avi] [--resolution=1920x1080] [--fps=60] [--windows|--linux]
#                        [-- teaser options: --attacker=N --target=N --seconds=S --spin=...]
#   out.avi       default .screenshots/teaser/homar_teaser.avi (git-ignored); relative paths are
#                 resolved against the current directory. The extension picks Godot's writer:
#                 .avi = MJPEG video + WAV audio in one file (~300 MB for 1080p60; plays in VLC),
#                 .png = one PNG per frame (out00000000.png, ...) plus out.wav
#   --resolution  window size = video size
#   --fps         frames per second of the video (also the simulation step)
#   after --       passed to tools/teaser.gd (other attacker / target, length, the --spin camera scout)
# The video has the game's own sound: forest ambience and birds from the start, then the rocket
# launches and the explosions of the impacts (AudioDirector, volume from the saved sound settings –
# a muted game records silence). Convert it with e.g.
#   ffmpeg -i homar_teaser.avi -c:v libx264 -crf 18 -pix_fmt yuv420p homar_teaser.mp4
#   --still=<s>   no film: save one frame (<s> seconds after the salvo start, e.g. 4.6) as the PNG `out`
#                 (use a .png name), no fade or title – the main menu's battle backdrop (tools/menu_backdrop.sh)
# Exit codes: 0 written, 1 script error or no recording, 124 timeout (20 min), 127 Godot not found.
set -uo pipefail
caller_dir="$PWD"
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# shellcheck source=tools/windows_godot.sh
source tools/windows_godot.sh

out=".screenshots/teaser/homar_teaser.avi"
resolution="1920x1080"
fps=60
platform=""
still=""
teaser_args=()
while [[ $# -gt 0 ]]; do
	case "$1" in
	--resolution=*) resolution="${1#*=}" ;;
	--fps=*) fps="${1#*=}" ;;
	--still=*) still="${1#*=}" ;;
	--windows) platform="windows" ;;
	--linux) platform="linux" ;;
	--)
		shift
		teaser_args=("$@")
		break
		;;
	*) out="$1" ;;
	esac
	shift
done
[[ "$out" != /* ]] && out="$caller_dir/$out"
mkdir -p "$(dirname "$out")"
touch .screenshots/.gdignore 2>/dev/null || true

godot_win="$(pick_windows_godot "$platform")" || exit 127
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/godot" ]]; then
	GODOT="$HOME/.local/bin/godot"
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Could not find '$GODOT'. Install it: tools/install_godot.sh or set GODOT=/path/to/godot" >&2
	exit 127
fi
# Refresh the class cache (class_name) for --script mode, like tools/render_unit.sh.
timeout 120 "$GODOT" --headless --path . --import >/dev/null 2>&1

if [[ -n "$still" ]]; then
	# The salvo only plays under the Movie Maker writer: record the film up to <s> seconds as a PNG
	# sequence in a temp folder and keep its last frame.
	frames="$(mktemp -d)"
	errors="$(mktemp)"
	output="$(mktemp)"
	trap 'rm -rf "$frames" "$errors" "$output"' EXIT
	still_args=(--still="$still")
	godot_args=(--resolution "$resolution" --fixed-fps "$fps" --script res://tools/teaser.gd)
	if [[ -n "$godot_win" ]]; then
		run_windows_godot "$godot_win" 900 "$output" "$errors" "$project_dir" \
			--write-movie "$(wslpath -w "$frames/f.png")" "${godot_args[@]}" -- "${still_args[@]}" "${teaser_args[@]}"
	else
		timeout 900 "$GODOT" --path . --write-movie "$frames/f.png" "${godot_args[@]}" \
			-- "${still_args[@]}" "${teaser_args[@]}" >"$output" 2>"$errors"
	fi
	if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
		cat "$errors" >&2
		echo "ERROR: the log contains script errors (see above)." >&2
		exit 1
	fi
	last="$(find "$frames" -name 'f*.png' | sort | tail -1)"
	if [[ -z "$last" ]]; then
		cat "$output" "$errors" >&2
		echo "ERROR: no frame was recorded." >&2
		exit 1
	fi
	cp "$last" "$out"
	echo "Still saved: $out"
	exit 0
fi

errors="$(mktemp)"
output="$(mktemp)"
trap 'rm -f "$errors" "$output"' EXIT
godot_args=(--resolution "$resolution" --fixed-fps "$fps" --script res://tools/teaser.gd)
if [[ -n "$godot_win" ]]; then
	run_windows_godot "$godot_win" 1200 "$output" "$errors" "$project_dir" \
		--write-movie "$(wslpath -w "$out")" "${godot_args[@]}" -- "${teaser_args[@]}"
	status=$?
else
	timeout 1200 "$GODOT" --path . --write-movie "$out" "${godot_args[@]}" -- "${teaser_args[@]}" \
		>"$output" 2>"$errors"
	status=$?
fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$errors"; then
	cat "$errors" >&2
	echo "ERROR: the log contains script errors (see above)." >&2
	exit 1
fi
# Godot's exit code after a Movie Maker run is not reliable (5 on a complete recording): success is
# its "Done recording movie" line.
if grep -q "Done recording movie" "$output"; then
	grep -E "frames at|Done recording" "$output"
	echo "Teaser saved: $out"
	exit 0
fi
cat "$output" "$errors" >&2
[[ $status -eq 0 ]] && status=1
exit $status
