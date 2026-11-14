#!/usr/bin/env bash
# Runs the game (needs a graphical environment – in WSL2 it works through WSLg).
# Usage: tools/run.sh [--editor] [--quality=low|high] [--scenario=<name>] [--scene=<name>] [--side=<id>] [--debug]
#   --quality  force the graphics quality (default: auto-detected; LOW on software rendering)
#   --scenario start the battle with that scenario (default_battle, objective_battle, command_points_battle, fire_support_battle, suwalki_battle)
#   --scene    open a scene directly instead of the main menu: staff_map (the operational staff map, TASK-093a), battle, menu
#   --debug    debug mode: the F9 panel on the staff map (user argument)
#   --side     the side the staff map is viewed as: nato (default) or russia (TASK-092b)
# The Godot path can be overridden with the GODOT variable.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

# tools/install_godot.sh installs to ~/.local/bin, which zsh does not have on PATH by default.
if ! command -v "$GODOT" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/godot" ]]; then
	GODOT="$HOME/.local/bin/godot"
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Could not find '$GODOT'. Install it: tools/install_godot.sh or set GODOT=/path/to/godot" >&2
	exit 127
fi

# Importing refreshes the class cache (class_name) – without it a fresh clone fails with "not declared in the current scope" errors.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

user_args=()
editor=0
scene=""
for arg in "$@"; do
	case "$arg" in
	--editor) editor=1 ;;
	--scene=*) scene="${arg#--scene=}" ;;
	--quality=* | --scenario=* | --side=* | --debug) user_args+=("$arg") ;;
	esac
done
if [[ $editor -eq 1 ]]; then
	exec "$GODOT" --path . --editor
fi
scene_path=()
case "$scene" in
"") ;;
staff_map) scene_path=(res://scenes/operational/staff_map.tscn) ;;
battle) scene_path=(res://scenes/battle/battle.tscn) ;;
menu) scene_path=(res://scenes/ui/main_menu.tscn) ;;
*)
	echo "Unknown --scene '$scene' (staff_map, battle, menu)" >&2
	exit 2
	;;
esac
if [[ ${#user_args[@]} -gt 0 ]]; then
	exec "$GODOT" --path . "${scene_path[@]}" -- "${user_args[@]}"
fi
exec "$GODOT" --path . "${scene_path[@]}"
