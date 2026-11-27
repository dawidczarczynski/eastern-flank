class_name StaffMapDefaults
extends RefCounted
## The few StaffMap values the main menu needs before the map exists. They live here so the menu
## does not pull the whole staff map script (and its dependency tree) into the startup load.

const DEFAULT_OPERATION := &"suwalki_gap"
## Campaign seed until the session carries one (TASK-094); nothing draws from the RNG yet.
const DEFAULT_SEED := 1

## Set by the main menu's DEVTOOLS page (TERRAIN VIEWER) and kept across the scene changes
## between the picker and the terrain view; the main menu clears it.
static var terrain_viewer_session := false
