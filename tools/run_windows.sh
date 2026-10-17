#!/usr/bin/env bash
# Runs the game with the Windows build of Godot (from WSL), so it renders on the GPU –
# under WSLg with an old Mesa the Linux build falls back to software rendering (llvmpipe).
# Usage: tools/run_windows.sh [--editor] [--import]
#   --editor  open the editor instead of the game
#   --import  refresh the class cache with the Linux Godot first (only needed after adding a
#             class_name without running tools/check.sh)
# The Windows Godot path can be set with GODOT_WIN (WSL path, e.g. /mnt/c/Godot/Godot_v4.5.1-stable_win64.exe);
# otherwise the usual places on C: are searched for the version below.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="4.5.1"
EXE="Godot_v${VERSION}-stable_win64.exe"

find_godot() {
	local candidate
	for candidate in \
		/mnt/c/Godot/"$EXE" \
		/mnt/c/Godot/*/"$EXE" \
		"/mnt/c/Program Files/Godot/$EXE" \
		/mnt/c/Users/*/Downloads/"$EXE" \
		/mnt/c/Users/*/Downloads/*/"$EXE" \
		/mnt/c/Users/*/Desktop/"$EXE" \
		/mnt/c/Users/*/Desktop/*/"$EXE"; do
		# The zip extracts to a folder with the same name as the exe – skip that folder.
		if [[ -f "$candidate" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

GODOT_WIN="${GODOT_WIN:-$(find_godot || true)}"
if [[ -z "$GODOT_WIN" || ! -f "$GODOT_WIN" ]]; then
	echo "Could not find $EXE. Download Godot $VERSION for Windows (standard, not .NET) from" >&2
	echo "https://godotengine.org/download/archive/${VERSION}-stable/ and unzip it to C:\\Godot," >&2
	echo "or set GODOT_WIN=/mnt/c/path/to/$EXE" >&2
	exit 127
fi

editor=()
for arg in "$@"; do
	case "$arg" in
	--editor) editor=(--editor) ;;
	--import)
		linux_godot="$(command -v "${GODOT:-godot}" || echo "$HOME/.local/bin/godot")"
		"$linux_godot" --headless --path . --import >/dev/null 2>&1 || true
		;;
	*)
		echo "Unknown argument: $arg. Usage: tools/run_windows.sh [--editor] [--import]" >&2
		exit 2
		;;
	esac
done

# Detached, so the terminal is free right away; Godot's own window shows the output.
nohup "$GODOT_WIN" --path "$(wslpath -w "$PWD")" "${editor[@]}" >/dev/null 2>&1 &
echo "Started $(basename "$GODOT_WIN") ${editor[*]}"
