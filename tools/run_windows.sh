#!/usr/bin/env bash
# Runs the game with the Windows build of Godot (from WSL), so it renders on the GPU –
# under WSLg with an old Mesa the Linux build falls back to software rendering (llvmpipe).
# Usage: tools/run_windows.sh [--editor] [--import] [--quality=low|high] [--scenario=<name>]
#   --quality  force the graphics quality (default: auto-detected, HIGH on the GPU); passed as a user argument
#   --scenario start the battle with that scenario (default_battle, objective_battle, command_points_battle); a user argument
#   --editor  open the editor instead of the game
#   --import  refresh the class cache with the Linux Godot first (only needed after adding a
#             class_name without running tools/check.sh)
# The Windows Godot path can be set with GODOT_WIN (WSL path, e.g. /mnt/c/Godot/Godot_v4.5.1-stable_win64.exe);
# otherwise the usual places on C: are searched (tools/windows_godot.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/windows_godot.sh
source tools/windows_godot.sh

GODOT_WIN="$(find_windows_godot || true)"
if [[ -z "$GODOT_WIN" ]]; then
	windows_godot_missing_help
	exit 127
fi

editor=()
user_args=()
for arg in "$@"; do
	case "$arg" in
	--editor) editor=(--editor) ;;
	--quality=* | --scenario=*) user_args+=("$arg") ;;
	--import)
		linux_godot="$(command -v "${GODOT:-godot}" || echo "$HOME/.local/bin/godot")"
		"$linux_godot" --headless --path . --import >/dev/null 2>&1 || true
		;;
	*)
		echo "Unknown argument: $arg. Usage: tools/run_windows.sh [--editor] [--import] [--quality=low|high] [--scenario=<name>]" >&2
		exit 2
		;;
	esac
done

# Started through PowerShell's Start-Process, so Godot doesn't depend on this WSL session:
# a process backgrounded here is killed when the session ends (e.g. `wsl tools/run_windows.sh`
# from Windows), and `cmd.exe /c start` blocks until Godot exits. The working directory is
# C: because Windows programs can't start in a WSL (UNC) directory.
args="'--path','$(wslpath -w "$PWD")'"
for arg in "${editor[@]}"; do
	args+=",'$arg'"
done
if [[ ${#user_args[@]} -gt 0 ]]; then
	args+=",'--'"
	for arg in "${user_args[@]}"; do
		args+=",'$arg'"
	done
fi
pid="$(cd /mnt/c && powershell.exe -NoProfile -NonInteractive -Command \
	"(Start-Process -FilePath '$(wslpath -w "$GODOT_WIN")' -ArgumentList $args -PassThru).Id" \
	</dev/null | tr -d '\r')"
echo "Started $(basename "$GODOT_WIN")${editor[*]:+ ${editor[*]}} (PID $pid)"
