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

# Second shot: the operational staff map (docs/images/staff_map.png) – Russian side to move, three
# marches planned and the order ring open on a hex. Hex coordinates are column·row as on the hex card.
SCREENSHOT_SCENE=staff_map \
	SCREENSHOT_STAFF_MAP="${SCREENSHOT_STAFF_MAP:-side:1,zoom:1.1,focus:42:48,order:ru_tank_2:41:52:1,order:ru_mlrs_2:50:48:1,order:ru_mr_5:43:44:1,select:ru_mr_4,ring:40:46}" \
	"$project_dir/tools/screenshot.sh" "$project_dir/docs/images/staff_map.png" "$@"

# Third and fourth: the main menu backdrops (assets/menu/, tools/menu_backdrop.sh).
"$project_dir/tools/menu_backdrop.sh"
