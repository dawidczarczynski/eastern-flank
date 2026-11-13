#!/usr/bin/env bash
# Runs the game with the Windows build of Godot (from WSL), so it renders on the GPU –
# under WSLg with an old Mesa the Linux build falls back to software rendering (llvmpipe).
# Usage: tools/run_windows.sh [--editor] [--import] [--local] [--quality=low|high] [--scenario=<name>] [--scene=<name>] [--side=<id>] [--debug]
#   --quality  force the graphics quality (default: auto-detected, HIGH on the GPU); passed as a user argument
#   --scenario start the battle with that scenario (default_battle, objective_battle, command_points_battle, suwalki_battle); a user argument
#   --scene   open a scene directly: staff_map, battle, menu (as in run.sh)
#   --side    the side the staff map is viewed as: nato (default) or russia; a user argument
#   --debug   debug mode: the F9 panel on the staff map; a user argument
#   --editor  open the editor instead of the game
#   --import  refresh the class cache with the Linux Godot first (only needed after adding a
#             class_name without running tools/check.sh)
#   --local   run from a copy of the game files on the Windows disk instead of the WSL path:
#             Windows reads \\wsl.localhost slowly, so the battle scene's scripts load in ~4.5 s
#             instead of ~18 s (measured). The copy (project.godot, .godot, addons, assets, data,
#             scenes, src; ~120 MB) is refreshed before every start – the first copy takes most
#             of a minute, later ones copy only the changed files. It lives in
#             %LOCALAPPDATA%\eastern-flank\run-copy (EF_LOCAL_COPY=<WSL path> overrides it); saves
#             and settings are in user:// either way. Not with --editor (edits would land in the copy).
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
local_copy=0
user_args=()
scene_path=()
for arg in "$@"; do
	case "$arg" in
	--editor) editor=(--editor) ;;
	--local) local_copy=1 ;;
	--quality=* | --scenario=* | --side=* | --debug) user_args+=("$arg") ;;
	--scene=*)
		case "${arg#--scene=}" in
		staff_map) scene_path=(res://scenes/operational/staff_map.tscn) ;;
		battle) scene_path=(res://scenes/battle/battle.tscn) ;;
		menu) scene_path=(res://scenes/ui/main_menu.tscn) ;;
		*) echo "Unknown --scene '${arg#--scene=}' (staff_map, battle, menu)" >&2; exit 2 ;;
		esac
		;;
	--import)
		linux_godot="$(command -v "${GODOT:-godot}" || echo "$HOME/.local/bin/godot")"
		"$linux_godot" --headless --path . --import >/dev/null 2>&1 || true
		;;
	*)
		echo "Unknown argument: $arg. Usage: tools/run_windows.sh [--editor] [--import] [--quality=low|high] [--scenario=<name>] [--scene=<name>] [--side=<id>] [--debug]" >&2
		exit 2
		;;
	esac
done

# --local: mirror the files the game reads to the Windows disk and run from there.
project_dir="$PWD"
if [[ $local_copy -eq 1 ]]; then
	if [[ ${#editor[@]} -gt 0 ]]; then
		echo "--local cannot be combined with --editor (edits would land in the copy)" >&2
		exit 2
	fi
	if ! command -v rsync >/dev/null 2>&1; then
		echo "--local needs rsync (sudo apt install rsync)" >&2
		exit 127
	fi
	project_dir="${EF_LOCAL_COPY:-}"
	if [[ -z "$project_dir" ]]; then
		app_data="$(cd /mnt/c && cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')"
		if [[ -z "$app_data" || "$app_data" == *%* ]]; then
			echo "Could not find %LOCALAPPDATA%; set EF_LOCAL_COPY=/mnt/c/some/folder" >&2
			exit 1
		fi
		project_dir="$(wslpath -u "$app_data")/eastern-flank/run-copy"
	fi
	mkdir -p "$project_dir"
	# Checking every file on the Windows side takes rsync ~15 s, so the copy keeps a manifest
	# (path, mtime, size) of what it was made from: later starts list the files on the WSL side
	# only (fast) and copy just the changed ones.
	manifest="$project_dir/.run-copy-manifest"
	current="$(mktemp)"
	changed="$(mktemp)"
	trap 'rm -f "$current" "$changed"' EXIT
	find project.godot .godot addons assets data scenes src \
		-path .godot/editor -prune -o -type f -printf '%p\t%T@\t%s\n' | LC_ALL=C sort >"$current"
	if [[ -f "$manifest" ]]; then
		LC_ALL=C comm -13 "$manifest" "$current" | cut -f1 >"$changed"
		if [[ -s "$changed" ]]; then
			rsync -a --files-from="$changed" ./ "$project_dir/"
		fi
		LC_ALL=C comm -23 <(cut -f1 "$manifest" | LC_ALL=C sort) <(cut -f1 "$current" | LC_ALL=C sort) |
			while IFS= read -r removed; do
				rm -f "$project_dir/$removed"
			done
	else
		rsync -a --delete --exclude='/.godot/editor/' \
			--include='/project.godot' --include='/.godot/***' --include='/addons/***' \
			--include='/assets/***' --include='/data/***' --include='/scenes/***' \
			--include='/src/***' --exclude='/*' ./ "$project_dir/"
		: >"$changed"
	fi
	cp "$current" "$manifest"
	echo "Game files in $project_dir are up to date"
fi

# Started through PowerShell's Start-Process, so Godot doesn't depend on this WSL session:
# a process backgrounded here is killed when the session ends (e.g. `wsl tools/run_windows.sh`
# from Windows), and `cmd.exe /c start` blocks until Godot exits. The working directory is
# C: because Windows programs can't start in a WSL (UNC) directory.
args="'--path','$(wslpath -w "$project_dir")'"
for arg in "${editor[@]}" "${scene_path[@]}"; do
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
