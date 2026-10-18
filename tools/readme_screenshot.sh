#!/usr/bin/env bash
# Renders the README gameplay shot (docs/images/gameplay.png): a close-up of the Polish force with the
# tank selected (reach wash + move path). Re-run after every visible change to the battle scene and
# commit the PNG together with the change. Read the PNG before committing – it must still look good.
# Usage: tools/readme_screenshot.sh   (same options, requirements and exit codes as tools/screenshot.sh;
#        under WSL it renders with the Windows Godot build – never commit a --linux render)
# The framing lives here: SCREENSHOT_CAMERA=<unit id>,<yaw degrees>,<distance>, SCREENSHOT_SELECT_UNIT=<unit id>.
# If the scenario changes and unit 2 is no longer a good subject, pick a new framing (try a few
# shots under .screenshots/ with tools/screenshot.sh and the same variables).
set -uo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
SCREENSHOT_SELECT_UNIT="${SCREENSHOT_SELECT_UNIT:-2}" \
	SCREENSHOT_CAMERA="${SCREENSHOT_CAMERA:-2,-40,11}" \
	"$project_dir/tools/screenshot.sh" "$project_dir/docs/images/gameplay.png" "$@"
